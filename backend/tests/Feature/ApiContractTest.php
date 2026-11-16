<?php

namespace Tests\Feature;

use Illuminate\Routing\Route as LaravelRoute;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

/**
 * Keeps docs/openapi.json and the registered /api/v1 routes in sync. Adding,
 * removing or renaming a route (or changing its auth requirement or token scope)
 * without updating the contract fails these tests.
 */
class ApiContractTest extends TestCase
{
    private const HTTP_METHODS = ['get', 'put', 'post', 'delete', 'patch', 'options', 'head'];

    /**
     * Route operations that are intentionally absent from the contract.
     * The MCP endpoint answers GET and DELETE with 405 as required by the
     * Streamable HTTP transport; only POST is a real operation.
     */
    private const UNDOCUMENTED = ['GET /mcp', 'DELETE /mcp'];

    /** @return array<string, mixed> */
    private function contract(): array
    {
        $contractPath = dirname(base_path()).'/docs/openapi.json';

        return json_decode((string) file_get_contents($contractPath), true, 512, JSON_THROW_ON_ERROR);
    }

    /**
     * @return array<string, LaravelRoute>
     */
    private function apiRoutes(): array
    {
        $routes = [];
        foreach (Route::getRoutes()->getRoutes() as $route) {
            if (! str_starts_with($route->uri(), 'api/v1/')) {
                continue;
            }
            $path = '/'.substr($route->uri(), strlen('api/v1/'));
            foreach ($route->methods() as $method) {
                if ($method === 'HEAD') {
                    continue;
                }
                $key = $method.' '.$path;
                if (! in_array($key, self::UNDOCUMENTED, true)) {
                    $routes[$key] = $route;
                }
            }
        }

        return $routes;
    }

    /**
     * @param  array<string, mixed>  $contract
     * @return array<string, array<string, mixed>>
     */
    private function operations(array $contract): array
    {
        $operations = [];
        foreach ($contract['paths'] as $path => $item) {
            foreach ($item as $method => $operation) {
                if (in_array($method, self::HTTP_METHODS, true)) {
                    $operations[strtoupper($method).' '.$path] = $operation;
                }
            }
        }

        return $operations;
    }

    public function test_every_route_is_documented_and_every_documented_operation_exists(): void
    {
        $documented = array_keys($this->operations($this->contract()));
        $registered = array_keys($this->apiRoutes());

        sort($documented);
        sort($registered);

        self::assertSame([], array_values(array_diff($registered, $documented)), 'Routes missing from docs/openapi.json');
        self::assertSame([], array_values(array_diff($documented, $registered)), 'Operations in docs/openapi.json without a route');
    }

    public function test_path_parameters_match_the_route_definitions(): void
    {
        $contract = $this->contract();
        $operations = $this->operations($contract);

        foreach ($this->apiRoutes() as $key => $route) {
            preg_match_all('/\{(\w+)\??\}/', $route->uri(), $matches);
            $expected = $matches[1];
            $declared = [];
            foreach ($operations[$key]['parameters'] ?? [] as $parameter) {
                $parameter = $this->resolve($contract, $parameter);
                if ($parameter['in'] === 'path') {
                    $declared[] = $parameter['name'];
                }
            }
            sort($expected);
            sort($declared);
            self::assertSame($expected, $declared, "Path parameters of {$key}");
        }
    }

    public function test_authentication_and_token_scope_match_the_route_middleware(): void
    {
        $operations = $this->operations($this->contract());

        foreach ($this->apiRoutes() as $key => $route) {
            $middleware = $route->gatherMiddleware();
            $secured = (bool) array_filter($middleware, static fn ($name): bool => is_string($name) && str_starts_with($name, 'auth.api:'));

            if (! $secured) {
                self::assertArrayNotHasKey('security', $operations[$key], "{$key} is public but documented as secured");

                continue;
            }

            self::assertArrayHasKey('security', $operations[$key], "{$key} requires authentication");

            $scopes = array_values(array_filter(
                array_map(static fn ($name) => is_string($name) && str_starts_with($name, 'token.scope') ? $name : null, $middleware),
            ));
            $explicit = array_values(array_filter($scopes, static fn (string $name): bool => str_contains($name, ':')));
            $expected = match (true) {
                $key === 'POST /auth/logout' => 'any',
                $explicit !== [] => substr(end($explicit), strlen('token.scope:')),
                in_array($route->methods()[0], ['GET'], true) => 'read',
                default => 'write',
            };

            self::assertSame($expected, $operations[$key]['x-token-scope'] ?? null, "Token scope of {$key}");
        }
    }

    public function test_operations_are_well_formed(): void
    {
        $contract = $this->contract();
        self::assertSame('3.1.0', $contract['openapi']);
        self::assertSame('v1', $contract['info']['version']);
        self::assertSame('/api/v1', $contract['servers'][0]['url']);

        $operationIDs = [];
        foreach ($this->operations($contract) as $key => $operation) {
            self::assertArrayHasKey('operationId', $operation, $key);
            self::assertArrayNotHasKey($operation['operationId'], $operationIDs, 'Duplicate operationId '.$operation['operationId']);
            $operationIDs[$operation['operationId']] = true;
            self::assertNotEmpty($operation['summary'] ?? null, "{$key} needs a summary");
            self::assertNotEmpty($operation['tags'] ?? null, "{$key} needs a tag");
            self::assertNotEmpty($operation['responses'] ?? null, "{$key} needs responses");
            self::assertArrayHasKey('429', $operation['responses'], "{$key} must document rate limiting");
            if (isset($operation['security'])) {
                self::assertArrayHasKey('401', $operation['responses'], $key);
                self::assertArrayHasKey('403', $operation['responses'], $key);
            }
            self::assertTrue(
                (bool) array_filter(array_keys($operation['responses']), static fn ($code): bool => str_starts_with((string) $code, '2')),
                "{$key} needs a success response",
            );
        }
    }

    public function test_every_reference_resolves_and_every_component_is_used(): void
    {
        $contract = $this->contract();
        $json = json_encode($contract, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES);

        preg_match_all('/"\$ref":"#\/components\/([A-Za-z]+)\/([A-Za-z0-9_]+)"/', $json, $matches, PREG_SET_ORDER);
        $used = [];
        foreach ($matches as [, $section, $name]) {
            self::assertArrayHasKey($name, $contract['components'][$section] ?? [], "Unresolved \$ref {$section}/{$name}");
            $used[$section.'/'.$name] = true;
        }

        foreach (['schemas', 'responses', 'parameters'] as $section) {
            foreach (array_keys($contract['components'][$section]) as $name) {
                self::assertArrayHasKey($section.'/'.$name, $used, "Unused component {$section}/{$name}");
            }
        }
    }

    public function test_contract_documents_the_error_envelope_and_both_pagination_styles(): void
    {
        $contract = $this->contract();

        self::assertSame(['error'], $contract['components']['schemas']['ErrorEnvelope']['required']);
        self::assertSame(['code', 'message'], $contract['components']['schemas']['Error']['required']);
        self::assertArrayHasKey('PageMeta', $contract['components']['schemas']);
        self::assertArrayHasKey('CursorMeta', $contract['components']['schemas']);
        self::assertArrayHasKey('401', $contract['paths']['/auth/apple']['post']['responses']);
        self::assertArrayHasKey('422', $contract['paths']['/auth/apple']['post']['responses']);
        self::assertContains('#/components/parameters/Cursor', array_map(
            static fn (array $parameter): string => $parameter['$ref'] ?? '',
            $contract['paths']['/me/recipes']['get']['parameters'],
        ));
    }

    /**
     * @param  array<string, mixed>  $contract
     * @param  array<string, mixed>  $node
     * @return array<string, mixed>
     */
    private function resolve(array $contract, array $node): array
    {
        if (! isset($node['$ref'])) {
            return $node;
        }

        $parts = explode('/', ltrim($node['$ref'], '#/'));
        $target = $contract;
        foreach ($parts as $part) {
            $target = $target[$part];
        }

        return $target;
    }
}
