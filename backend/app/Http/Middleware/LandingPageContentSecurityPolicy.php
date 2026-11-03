<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Symfony\Component\HttpFoundation\Response;

class LandingPageContentSecurityPolicy
{
    public function handle(Request $request, Closure $next): Response
    {
        $response = $next($request);
        $response->headers->set('Referrer-Policy', 'strict-origin');

        if (! config('analytics.consent_enabled')) {
            $response->headers->set('Content-Security-Policy', implode('; ', [
                "default-src 'self'",
                "script-src 'self'",
                "style-src 'self'",
                "img-src 'self'",
                "connect-src 'self'",
                "font-src 'self'",
                "object-src 'none'",
                "base-uri 'self'",
                "form-action 'self'",
                "frame-ancestors 'none'",
            ]));

            return $response;
        }

        $scriptSources = ["script-src 'self'"];
        $connectSources = ["connect-src 'self'"];
        $imageSources = ["img-src 'self'"];

        if (config('analytics.gtm_container_id') || config('analytics.ga4_measurement_id')) {
            $scriptSources[] = 'https://www.googletagmanager.com';
        }

        if (config('analytics.gtm_container_id')) {
            $connectSources[] = 'https://www.googletagmanager.com';
        }

        if (config('analytics.ga4_measurement_id')) {
            $connectSources[] = 'https://www.google-analytics.com';
            $connectSources[] = 'https://region1.google-analytics.com';
            $imageSources[] = 'https://www.google-analytics.com';
        }

        $response->headers->set('Content-Security-Policy', implode('; ', [
            "default-src 'self'",
            implode(' ', $scriptSources),
            "style-src 'self'",
            implode(' ', $imageSources),
            implode(' ', $connectSources),
            "font-src 'self'",
            "object-src 'none'",
            "base-uri 'self'",
            "form-action 'self'",
            "frame-ancestors 'none'",
        ]));

        return $response;
    }
}
