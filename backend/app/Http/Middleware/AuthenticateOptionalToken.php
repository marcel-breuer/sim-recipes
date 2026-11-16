<?php

namespace App\Http\Middleware;

use App\Models\User;
use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Lets public read endpoints recognise the caller when a valid bearer token is
 * sent, so owners can read their private recipes and viewer-specific state
 * (blocks, follow state) is applied. Requests without a token, with an invalid
 * or expired token, from suspended accounts, or with a token lacking the `read`
 * scope stay anonymous. This middleware never rejects a request.
 */
class AuthenticateOptionalToken
{
    public function handle(Request $request, Closure $next): Response
    {
        $defaultGuard = Auth::getDefaultDriver();

        if ($request->bearerToken() !== null) {
            $user = Auth::guard('sanctum')->user();
            $token = $user?->currentAccessToken();

            if ($user instanceof User && ! $user->is_suspended && $token !== null && $token->can('read')) {
                Auth::shouldUse('sanctum');
            }
        }

        try {
            return $next($request);
        } finally {
            Auth::shouldUse($defaultGuard);
        }
    }
}
