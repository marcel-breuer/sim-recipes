<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/**
 * @property array{service: string, status: string, version: string} $resource
 */
final class HealthResource extends JsonResource
{
    /**
     * @return array{service: string, status: string, version: string}
     */
    public function toArray(Request $request): array
    {
        return [
            'service' => $this->resource['service'],
            'status' => $this->resource['status'],
            'version' => $this->resource['version'],
        ];
    }
}
