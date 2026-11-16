<?php

namespace App\Mcp\Tools;

use App\Mcp\Support\InternalApiClient;
use Illuminate\Contracts\JsonSchema\JsonSchema;
use Illuminate\JsonSchema\Types\Type;
use Laravel\Mcp\Request;
use Laravel\Mcp\Response;
use Laravel\Mcp\Server\Tool;

/**
 * An MCP tool that is a thin, typed facade over exactly one REST endpoint.
 *
 * Parameters are whitelisted from the tool definition, so a client cannot inject
 * fields or paths that the definition does not declare. The REST layer remains
 * the single source of truth for validation, authorization and scopes.
 *
 * Parameter spec keys: name, in (path|query|body), type
 * (string|integer|boolean|string_list|settings|id_list), required, description,
 * enum, min, max.
 */
class ApiTool extends Tool
{
    private const SAFE_PATH_VALUE = '/^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$/';

    /**
     * @param  array<int, array<string, mixed>>  $params
     * @param  array{readOnly: bool, destructive: bool, idempotent: bool}  $hints
     */
    public function __construct(
        string $name,
        string $title,
        string $description,
        private readonly string $method,
        private readonly string $path,
        private readonly array $params,
        private readonly array $hints,
    ) {
        $this->name = $name;
        $this->title = $title;
        $this->description = $description;
    }

    public function requiredScope(): string
    {
        return $this->hints['readOnly'] ? 'read' : 'write';
    }

    /**
     * Hide write tools from clients whose token cannot use them, so an agent
     * with a read-only token is never offered actions it cannot perform.
     */
    public function shouldRegister(): bool
    {
        $token = request()->user()?->currentAccessToken();

        return $token === null || $token->can($this->requiredScope());
    }

    /**
     * @return array<string, mixed>
     */
    public function annotations(): array
    {
        return [
            'readOnlyHint' => $this->hints['readOnly'],
            'destructiveHint' => ! $this->hints['readOnly'] && $this->hints['destructive'],
            'idempotentHint' => $this->hints['idempotent'],
            'openWorldHint' => false,
        ];
    }

    /**
     * @return array<string, mixed>
     */
    public function schema(JsonSchema $schema): array
    {
        $properties = [];
        foreach ($this->params as $param) {
            $type = $this->typeFor($schema, $param);
            $type->description((string) $param['description']);
            if (($param['required'] ?? false) === true) {
                $type->required();
            }
            $properties[$param['name']] = $type;
        }

        return $properties;
    }

    public function handle(Request $request, InternalApiClient $api): Response
    {
        $token = $request->user()?->currentAccessToken();
        if ($token === null || ! $token->can($this->requiredScope())) {
            return Response::error(json_encode(['error' => [
                'code' => 'insufficient_scope',
                'message' => 'This tool requires the "'.$this->requiredScope().'" token scope.',
            ]], JSON_THROW_ON_ERROR));
        }

        $path = $this->path;
        $query = [];
        $body = [];
        $arguments = $request->all();

        foreach ($this->params as $param) {
            $key = $param['name'];
            $present = array_key_exists($key, $arguments) && $arguments[$key] !== null;

            if (! $present) {
                if (($param['required'] ?? false) === true) {
                    return $this->failure(422, 'validation_failed', 'The "'.$key.'" argument is required.');
                }

                continue;
            }

            $value = $arguments[$key];
            if ($param['in'] === 'path') {
                $substituted = $this->substitute($path, $key, $value);
                if ($substituted === null) {
                    return $this->failure(422, 'validation_failed', 'The "'.$key.'" argument is not a valid identifier.');
                }
                $path = $substituted;
            } elseif ($param['in'] === 'query') {
                $query[$key] = $value;
            } else {
                $body[$key] = $value;
            }
        }

        $result = $api->call($this->method, $path, $query, $body);

        if ($result['status'] >= 400) {
            return Response::error(json_encode(
                ($result['body'] ?? ['error' => ['code' => 'server_error', 'message' => 'The request failed.']])
                    + ['http_status' => $result['status']],
                JSON_THROW_ON_ERROR,
            ));
        }

        return $result['body'] === null
            ? Response::text('Done.')
            : Response::json($result['body']);
    }

    private function substitute(string $path, string $key, mixed $value): ?string
    {
        if (! is_string($value) || preg_match(self::SAFE_PATH_VALUE, $value) !== 1) {
            return null;
        }

        return str_replace('{'.$key.'}', rawurlencode($value), $path);
    }

    private function failure(int $status, string $code, string $message): Response
    {
        return Response::error(json_encode(
            ['error' => ['code' => $code, 'message' => $message], 'http_status' => $status],
            JSON_THROW_ON_ERROR,
        ));
    }

    /**
     * @param  array<string, mixed>  $param
     */
    private function typeFor(JsonSchema $schema, array $param): Type
    {
        $type = match ($param['type']) {
            'integer' => $schema->integer(),
            'boolean' => $schema->boolean(),
            'string_list', 'id_list' => $schema->array()->items($schema->string()),
            'settings' => $schema->array()->items($schema->object([
                'setting_key' => $schema->string()->description('Capability key from get_camera, e.g. "film_simulation".')->required(),
                'value' => $schema->anyOf([
                    $schema->string(),
                    $schema->number(),
                    $schema->boolean(),
                    $schema->object(),
                ])->description('Value allowed by that capability for the recipe\'s camera model.')->required(),
            ])),
            default => $schema->string(),
        };

        if (isset($param['enum'])) {
            $type->enum($param['enum']);
        }
        if (isset($param['min']) && method_exists($type, 'min')) {
            $type->min($param['min']);
        }
        if (isset($param['max']) && method_exists($type, 'max')) {
            $type->max($param['max']);
        }

        return $type;
    }
}
