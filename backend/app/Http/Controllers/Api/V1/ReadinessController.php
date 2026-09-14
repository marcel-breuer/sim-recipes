<?php

namespace App\Http\Controllers\Api\V1;

use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Redis;
use Throwable;

final class ReadinessController
{
    public function __invoke(): JsonResponse
    {
        $checks = [
            'database' => $this->checkDatabase(),
            'redis' => $this->checkRedis(),
        ];
        $ready = ! in_array(false, $checks, true);

        return response()->json([
            'data' => [
                'service' => 'sim-recipes-api',
                'status' => $ready ? 'ok' : 'degraded',
                'checks' => $checks,
            ],
        ], $ready ? 200 : 503);
    }

    private function checkDatabase(): bool
    {
        try {
            DB::select('select 1');
        } catch (Throwable) {
            return false;
        }

        return true;
    }

    private function checkRedis(): bool
    {
        try {
            Redis::connection()->ping();
        } catch (Throwable) {
            return false;
        }

        return true;
    }
}
