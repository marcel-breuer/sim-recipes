<?php

namespace App\Http\Resources\Api\V1;

use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\User;
use Carbon\CarbonInterface;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Recipe */
class RecipeResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $camera = $this->resource->relationLoaded('cameraModel') ? $this->resource->getRelation('cameraModel') : null;
        $user = $this->resource->relationLoaded('user') ? $this->resource->getRelation('user') : null;
        $provenance = $this->resource->relationLoaded('provenance')
            ? $this->resource->getRelation('provenance')
            : null;
        $publishedAt = $this->resource->getAttribute('published_at');

        return [
            'id' => $this->resource->getKey(),
            'name' => $this->resource->getAttribute('name'),
            'description' => $this->resource->getAttribute('description'),
            'recommendation' => $this->resource->getAttribute('recommendation'),
            'lens' => $this->resource->getAttribute('lens'),
            'status' => $this->resource->getAttribute('status'),
            'published_at' => $publishedAt instanceof CarbonInterface ? $publishedAt->toISOString() : null,
            'camera_model' => $camera instanceof CameraModel ? [
                'id' => $camera->getKey(),
                'name' => $camera->getAttribute('name'),
                'slug' => $camera->getAttribute('slug'),
            ] : null,
            'author' => $user instanceof User ? [
                'id' => $user->getKey(),
                'name' => $user->getAttribute('name'),
            ] : null,
            'provenance' => $provenance !== null ? [
                'source_recipe_id' => $provenance->getAttribute('source_recipe_id'),
                'source_author_id' => $provenance->getAttribute('source_author_id'),
            ] : null,
            'categories' => CategoryResource::collection($this->resource->relationLoaded('categories') ? $this->resource->getRelation('categories') : []),
            'tags' => TagResource::collection($this->resource->relationLoaded('tags') ? $this->resource->getRelation('tags') : []),
            'settings' => RecipeSettingResource::collection($this->resource->relationLoaded('settings') ? $this->resource->getRelation('settings') : []),
            'images' => RecipeImageResource::collection($this->resource->relationLoaded('images') ? $this->resource->getRelation('images') : []),
        ];
    }
}
