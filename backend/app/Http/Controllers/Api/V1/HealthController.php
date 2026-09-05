<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Resources\Api\V1\HealthResource;

final class HealthController
{
    public function __invoke(): HealthResource
    {
        return new HealthResource([
            'service' => 'sim-recipes-api',
            'status' => 'ok',
            'version' => 'v1',
        ]);
    }
}
