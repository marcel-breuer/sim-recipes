<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class RejectSuspendedUsers
{
    public function handle(Request $request, Closure $next): Response
    {
        if ($request->user()?->is_suspended === true) {
            throw new AuthenticationException('This account has been suspended.');
        }

        return $next($request);
    }
}
