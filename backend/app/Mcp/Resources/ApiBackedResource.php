<?php

namespace App\Mcp\Resources;

use App\Mcp\Support\InternalApiClient;
use Laravel\Mcp\Response;
use Laravel\Mcp\ResponseFactory;
use Laravel\Mcp\Server\Resource;

/**
 * Read-only MCP resource backed by one REST GET endpoint, executed with the
 * caller's own token and therefore with the caller's own visibility.
 */
abstract class ApiBackedResource extends Resource
{
    protected string $mimeType = 'application/json';

    /**
     * @param  array<string, mixed>  $query
     */
    protected function fetch(InternalApiClient $api, string $path, array $query = []): Response|ResponseFactory
    {
        $result = $api->call('GET', $path, $query);

        if ($result['status'] >= 400) {
            return Response::error(json_encode($result['body'] ?? ['error' => ['code' => 'server_error']], JSON_THROW_ON_ERROR));
        }

        return Response::text(json_encode($result['body'], JSON_THROW_ON_ERROR));
    }
}
