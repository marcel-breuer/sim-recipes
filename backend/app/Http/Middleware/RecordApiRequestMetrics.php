<?php

namespace App\Http\Middleware;

use App\Support\Observability\DatabaseQueryMetrics;
use Closure;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Database\Eloquent\ModelNotFoundException;
use Illuminate\Http\Exceptions\HttpResponseException;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpFoundation\Response;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;
use Throwable;

final class RecordApiRequestMetrics
{
    public function handle(Request $request, Closure $next): Response
    {
        $metrics = app(DatabaseQueryMetrics::class);
        $metrics->reset();
        $startedAtNanoseconds = hrtime(true);
        $status = 500;

        try {
            $response = $next($request);
            $status = $response->getStatusCode();

            return $response;
        } catch (Throwable $exception) {
            $status = match (true) {
                $exception instanceof ValidationException => 422,
                $exception instanceof AuthenticationException => 401,
                $exception instanceof AuthorizationException => 403,
                $exception instanceof ModelNotFoundException => 404,
                $exception instanceof HttpResponseException => $exception->getResponse()->getStatusCode(),
                $exception instanceof HttpExceptionInterface => $exception->getStatusCode(),
                default => 500,
            };

            throw $exception;
        } finally {
            $queryMetrics = $metrics->snapshot();
            $routeName = $request->route()?->getName();

            $context = [
                'route' => is_string($routeName) ? $routeName : 'unmatched',
                'method' => $request->method(),
                'status' => $status,
                'duration_ms' => round((hrtime(true) - $startedAtNanoseconds) / 1_000_000, 2),
                'db_query_count' => $queryMetrics['query_count'],
                'db_duration_ms' => $queryMetrics['duration_ms'],
            ];

            if ($routeName === 'api.v1.recipes.index') {
                $feed = $request->query('feed', 'popular');
                if (in_array($feed, ['popular', 'newest'], true)) {
                    $context['feed'] = $feed;
                }
            }

            Log::channel('stderr')->info('api.request.completed', $context);
        }
    }
}
