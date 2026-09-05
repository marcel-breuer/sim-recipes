<?php

return [
    'pagination' => [
        'default_per_page' => (int) env('API_DEFAULT_PER_PAGE', 20),
        'max_per_page' => (int) env('API_MAX_PER_PAGE', 100),
    ],
];
