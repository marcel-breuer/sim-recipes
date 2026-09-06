<?php

namespace App\Http\Resources\Api\V1;

use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\RecipeImage;
use App\Models\User;
use Carbon\CarbonInterface;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin Recipe */
class AdminRecipeResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $camera = $this->resource->relationLoaded('cameraModel')
            ? $this->resource->getRelation('cameraModel')
            : null;
        $user = $this->resource->relationLoaded('user')
            ? $this->resource->getRelation('user')
            : null;
        $publishedAt = $this->resource->getAttribute('published_at');

        return [
            'id' => $this->resource->getKey(),
            'name' => $this->resource->getAttribute('name'),
            'description' => $this->resource->getAttribute('description'),
            'recommendation' => $this->resource->getAttribute('recommendation'),
            'lens' => $this->resource->getAttribute('lens'),
            'status' => $this->resource->getAttribute('status'),
            'is_hidden' => (bool) $this->resource->getAttribute('is_hidden'),
            'moderated_at' => $this->resource->getAttribute('moderated_at')?->toISOString(),
            'moderation_reason' => $this->resource->getAttribute('moderation_reason'),
            'published_at' => $publishedAt instanceof CarbonInterface ? $publishedAt->toISOString() : null,
            'views_count' => (int) $this->resource->getAttribute('views_count'),
            'likes_count' => (int) $this->resource->getAttribute('likes_count'),
            'downloads_count' => (int) $this->resource->getAttribute('downloads_count'),
            'camera_model' => $camera instanceof CameraModel ? [
                'id' => $camera->getKey(),
                'name' => $camera->getAttribute('name'),
                'slug' => $camera->getAttribute('slug'),
            ] : null,
            'owner' => $user instanceof User ? [
                'id' => $user->getKey(),
                'name' => $user->getAttribute('name'),
            ] : null,
            'categories' => CategoryResource::collection($this->resource->relationLoaded('categories') ? $this->resource->getRelation('categories') : []),
            'tags' => TagResource::collection($this->resource->relationLoaded('tags') ? $this->resource->getRelation('tags') : []),
            'settings' => RecipeSettingResource::collection($this->resource->relationLoaded('settings') ? $this->resource->getRelation('settings') : []),
            'images' => $this->resource->relationLoaded('images')
                ? $this->resource->getRelation('images')->map(static fn (RecipeImage $image): array => [
                    'id' => $image->getKey(),
                    'mime_type' => $image->getAttribute('mime_type'),
                    'width' => $image->getAttribute('width'),
                    'height' => $image->getAttribute('height'),
                    'sort_order' => $image->getAttribute('sort_order'),
                    'processing_status' => $image->getAttribute('processing_status'),
                ])->values()->all()
                : [],
        ];
    }
}
