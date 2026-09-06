<?php

namespace App\Http\Controllers\Api\V1;

use Illuminate\Http\JsonResponse;

class SupportController
{
    public function __invoke(): JsonResponse
    {
        $baseURL = rtrim((string) config('app.url'), '/');

        return response()->json([
            'data' => [
                'support_email' => config('moderation.support_email'),
                'community_standards_url' => $baseURL.'/docs/community-standards',
                'privacy_policy_url' => $baseURL.'/privacy',
            ],
        ]);
    }
}
