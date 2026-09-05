<?php

return [
    'support_email' => env('SUPPORT_EMAIL', 'support@simrecipes.app'),
    'blocked_patterns' => [
        '\\bporn(?:ography)?\\b',
        '\\bsexual exploitation\\b',
        '\\bchild sexual abuse\\b',
        '\\bkill yourself\\b',
    ],
];
