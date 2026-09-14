<?php

return [
    'images' => [
        'max_per_recipe' => 5,
        'max_original_bytes' => 25 * 1024 * 1024,
        'user_quota_bytes' => 5 * 1024 * 1024 * 1024,
        'derivatives' => [
            'thumbnail' => 480,
            'detail' => 1600,
        ],
        'metadata' => [
            'originals' => 'retained privately while a recipe is private; never served after publication',
            'derivatives' => 'EXIF and GPS metadata stripped during WebP encoding',
        ],
    ],
];
