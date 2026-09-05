<?php

namespace App\Http\Resources\Api\V1;

use App\Models\CameraCapability;
use Illuminate\Database\Eloquent\Collection;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class CameraModelResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $capabilities = $this->resource->relationLoaded('capabilities')
            ? $this->resource->getRelation('capabilities')
            : [];

        return [
            'id' => $this->resource->getKey(),
            'manufacturer' => $this->resource->getAttribute('manufacturer'),
            'name' => $this->resource->getAttribute('name'),
            'slug' => $this->resource->getAttribute('slug'),
            'model_identifier' => $this->resource->getAttribute('model_identifier'),
            'is_supported' => $this->resource->getAttribute('is_supported'),
            'capabilities' => CameraCapabilityResource::collection(
                $capabilities instanceof Collection
                    ? $capabilities->filter(static fn (mixed $capability): bool => $capability instanceof CameraCapability)
                    : [],
            ),
        ];
    }
}
