<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Log;
use Illuminate\Support\Str;
use Symfony\Component\HttpFoundation\Response;

final class RequestId
{
    public function handle(Request $request, Closure $next): Response
    {
        $requestID = $request->header('X-Request-ID');
        if (! is_string($requestID) || ! preg_match('/^[A-Za-z0-9._-]{1,100}$/', $requestID)) {
            $requestID = (string) Str::uuid();
        }

        Log::withContext(['request_id' => $requestID]);

        return $next($request)->header('X-Request-ID', $requestID);
    }
}
