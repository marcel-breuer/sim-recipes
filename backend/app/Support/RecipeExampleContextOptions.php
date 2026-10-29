<?php

namespace App\Support;

final class RecipeExampleContextOptions
{
    public const SUBJECTS = [
        'street', 'portrait', 'landscape', 'architecture', 'nature', 'wildlife', 'travel', 'automotive',
        'night', 'low_light', 'indoor', 'food', 'everyday', 'documentary', 'close_up',
    ];

    public const LIGHTING = [
        'daylight', 'golden_hour', 'blue_hour', 'overcast', 'open_shade', 'backlit', 'artificial', 'mixed',
        'low_light', 'studio',
    ];

    public const LOOKS = [
        'warm', 'neutral', 'cool', 'monochrome', 'vibrant', 'muted', 'cinematic', 'vintage',
    ];
}
