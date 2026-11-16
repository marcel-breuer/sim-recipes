<?php

return [
    'auth_token_expiration_days' => (int) env('API_AUTH_TOKEN_EXPIRATION_DAYS', 30),

    'pagination' => [
        'default_per_page' => (int) env('API_DEFAULT_PER_PAGE', 20),
        'max_per_page' => (int) env('API_MAX_PER_PAGE', 100),
    ],

    /*
    | Personal access tokens are issued by an authenticated first-party session
    | (the iOS app) for automation clients such as scripts and MCP clients.
    | `read` allows safe (GET/HEAD) requests, `write` allows mutations. A token
    | never gains access to admin endpoints or to token management.
    */
    'personal_tokens' => [
        'abilities' => ['read', 'write'],
        'max_active' => (int) env('API_PERSONAL_TOKEN_MAX_ACTIVE', 10),
        'default_expiration_days' => (int) env('API_PERSONAL_TOKEN_DEFAULT_DAYS', 30),
        'max_expiration_days' => (int) env('API_PERSONAL_TOKEN_MAX_DAYS', 365),
    ],

    /*
    | Requests per minute. Authenticated clients are limited per user, anonymous
    | clients per IP address. Exceeding a limit returns HTTP 429 with the
    | standard error envelope and a Retry-After header.
    */
    'rate_limits' => [
        'read' => (int) env('API_RATE_LIMIT_READ', 120),
        'write' => (int) env('API_RATE_LIMIT_WRITE', 60),
        'auth' => (int) env('API_RATE_LIMIT_AUTH', 10),
        'mcp' => (int) env('API_RATE_LIMIT_MCP', 60),
    ],
];
