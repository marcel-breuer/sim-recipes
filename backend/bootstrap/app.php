<?php

use App\Http\Middleware\AuthenticateOptionalToken;
use App\Http\Middleware\EnforceIdempotency;
use App\Http\Middleware\EnforceTokenScope;
use App\Http\Middleware\EnsureAdmin;
use App\Http\Middleware\LandingPageContentSecurityPolicy;
use App\Http\Middleware\PreventIndexing;
use App\Http\Middleware\RecordApiRequestMetrics;
use App\Http\Middleware\RejectSuspendedUsers;
use App\Http\Middleware\RequestId;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Auth\Middleware\Authenticate;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Illuminate\Validation\ValidationException;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        api: __DIR__.'/../routes/api.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        $middleware->append(RequestId::class);
        $middleware->appendToGroup('api', RecordApiRequestMetrics::class);
        $middleware->alias([
            'auth.api' => Authenticate::class,
            'active.account' => RejectSuspendedUsers::class,
            'admin' => EnsureAdmin::class,
            'auth.optional' => AuthenticateOptionalToken::class,
            'idempotent' => EnforceIdempotency::class,
            'token.scope' => EnforceTokenScope::class,
            'landing.csp' => LandingPageContentSecurityPolicy::class,
            'noindex' => PreventIndexing::class,
        ]);
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );

        $exceptions->render(function (ValidationException $exception, Request $request) {
            if (! $request->is('api/*')) {
                return null;
            }

            return response()->json([
                'error' => [
                    'code' => 'validation_failed',
                    'message' => 'The given data was invalid.',
                    'details' => $exception->errors(),
                ],
            ], 422);
        });

        $exceptions->render(function (AuthenticationException $exception, Request $request) {
            if (! $request->is('api/*')) {
                return null;
            }

            return response()->json([
                'error' => [
                    'code' => 'unauthenticated',
                    'message' => 'Authentication is required.',
                ],
            ], 401);
        });

        $exceptions->render(function (Throwable $exception, Request $request) {
            if (! $request->is('api/*')) {
                return null;
            }

            $status = $exception instanceof HttpExceptionInterface
                ? $exception->getStatusCode()
                : 500;

            [$code, $message] = match ($status) {
                400 => ['bad_request', 'The request could not be processed.'],
                403 => ['forbidden', 'You are not allowed to perform this action.'],
                404 => ['not_found', 'The requested resource was not found.'],
                405 => ['method_not_allowed', 'The requested method is not allowed.'],
                409 => ['conflict', 'The request conflicts with the current state of the resource.'],
                422 => ['unprocessable', 'The request could not be processed.'],
                429 => ['rate_limited', 'Too many requests. Retry after the indicated delay.'],
                default => ['server_error', 'An unexpected error occurred.'],
            };

            if ($status === 422 && $exception->getMessage() !== '') {
                $message = $exception->getMessage();
            }

            $headers = $exception instanceof HttpExceptionInterface
                ? array_intersect_key($exception->getHeaders(), array_flip(['Retry-After', 'X-RateLimit-Limit', 'X-RateLimit-Remaining', 'Allow']))
                : [];

            return response()->json([
                'error' => [
                    'code' => $code,
                    'message' => $message,
                ],
            ], $status, $headers);
        });
    })->create();
