<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

/**
 * Enforces the ability scopes of Sanctum personal access tokens.
 *
 * Without parameters the required scope follows the HTTP method: safe methods
 * need `read`, every other method needs `write`. Explicit parameters list the
 * accepted scopes (any of them); the special scope `full` accepts only an
 * unrestricted (`*`) token, such as the one issued by Sign in with Apple, so
 * personal access tokens cannot reach token management or admin endpoints.
 */
class EnforceTokenScope
{
    public function handle(Request $request, Closure $next, string ...$scopes): Response
    {
        $user = $request->user();
        $token = $user?->currentAccessToken();

        if ($user === null || $token === null) {
            return $next($request);
        }

        $accepted = $scopes !== []
            ? $scopes
            : [in_array($request->method(), ['GET', 'HEAD', 'OPTIONS'], true) ? 'read' : 'write'];

        if (! $this->allows($token, $accepted)) {
            return response()->json([
                'error' => [
                    'code' => 'insufficient_scope',
                    'message' => 'The access token does not have the required scope.',
                    'details' => ['required_scopes' => array_values(array_diff($accepted, ['full']))],
                ],
            ], 403);
        }

        return $next($request);
    }

    /**
     * @param  array<int, string>  $accepted
     */
    private function allows(mixed $token, array $accepted): bool
    {
        if (! is_object($token) || ! method_exists($token, 'can')) {
            return false;
        }

        $unrestricted = $token->can('*');

        foreach ($accepted as $scope) {
            if ($scope === 'full' ? $unrestricted : $token->can($scope)) {
                return true;
            }
        }

        return false;
    }
}
