<?php

namespace App\Mcp\Support;

use Illuminate\Contracts\Debug\ExceptionHandler;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Routing\Router;
use Symfony\Component\HttpFoundation\Response;
use Throwable;

/**
 * Executes a REST API request in-process on behalf of the current MCP caller.
 *
 * MCP tools never talk to the database or to policies directly. Every call is
 * routed through the public `/api/v1` routes with the caller's own bearer token,
 * so authentication, token scopes, rate limits, validation, policies and
 * resources are exactly the ones REST clients get. There is no second code path
 * that could drift from or bypass the REST behaviour.
 */
class InternalApiClient
{
    public function __construct(
        private readonly Router $router,
        private readonly ExceptionHandler $exceptions,
    ) {}

    /**
     * @param  array<string, mixed>  $query
     * @param  array<string, mixed>  $body
     * @return array{status: int, body: array<string, mixed>|null}
     */
    public function call(string $method, string $path, array $query = [], array $body = []): array
    {
        $outer = app('request');
        $headers = ['HTTP_ACCEPT' => 'application/json'];
        $bearer = $outer->bearerToken();
        if ($bearer !== null) {
            $headers['HTTP_AUTHORIZATION'] = 'Bearer '.$bearer;
        }

        $uri = '/api/v1'.$path;
        $isRead = $method === 'GET';
        $content = null;
        if (! $isRead && $body !== []) {
            $headers['CONTENT_TYPE'] = 'application/json';
            $content = json_encode($body, JSON_THROW_ON_ERROR);
        }

        $inner = Request::create($uri, $method, $isRead ? $query : [], [], [], $headers, $content);

        app()->instance('request', $inner);

        try {
            try {
                $response = $this->router->dispatch($inner);
            } catch (Throwable $exception) {
                $this->exceptions->report($exception);
                $response = $this->exceptions->render($inner, $exception);
            }
        } finally {
            app()->instance('request', $outer);
        }

        return ['status' => $response->getStatusCode(), 'body' => $this->decode($response)];
    }

    /**
     * @return array<string, mixed>|null
     */
    private function decode(Response $response): ?array
    {
        if ($response instanceof JsonResponse) {
            $decoded = $response->getData(true);

            return is_array($decoded) ? $decoded : null;
        }

        $content = (string) $response->getContent();
        if ($content === '') {
            return null;
        }

        $decoded = json_decode($content, true);

        return is_array($decoded) ? $decoded : null;
    }
}
