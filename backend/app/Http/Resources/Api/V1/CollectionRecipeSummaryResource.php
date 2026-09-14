<?php

namespace App\Http\Resources\Api\V1;

use App\Models\CameraModel;
use Carbon\CarbonInterface;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class CollectionRecipeSummaryResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $camera = $this->resource->relationLoaded('cameraModel')
            ? $this->resource->getRelation('cameraModel')
            : null;
        $publishedAt = $this->resource->getAttribute('published_at');

        return [
            'id' => $this->resource->getKey(),
            'name' => $this->resource->getAttribute('name'),
            'description' => $this->resource->getAttribute('description'),
            'camera_model' => $camera instanceof CameraModel ? [
                'id' => $camera->getKey(),
                'name' => $camera->getAttribute('name'),
                'slug' => $camera->getAttribute('slug'),
            ] : null,
            'published_at' => $publishedAt instanceof CarbonInterface ? $publishedAt->toISOString() : null,
        ];
    }
}
