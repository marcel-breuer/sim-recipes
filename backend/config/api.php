<?php

return [
    'auth_token_expiration_days' => (int) env('API_AUTH_TOKEN_EXPIRATION_DAYS', 30),

    'pagination' => [
        'default_per_page' => (int) env('API_DEFAULT_PER_PAGE', 20),
        'max_per_page' => (int) env('API_MAX_PER_PAGE', 100),
    ],
];
