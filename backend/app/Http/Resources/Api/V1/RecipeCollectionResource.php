<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class RecipeCollectionResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $recipes = $this->resource->relationLoaded('recipes')
            ? $this->resource->getRelation('recipes')
            : [];

        return [
            'id' => $this->resource->getKey(),
            'name' => $this->resource->getAttribute('name'),
            'is_public' => (bool) $this->resource->getAttribute('is_public'),
            'sort_order' => (int) $this->resource->getAttribute('sort_order'),
            'recipes' => CollectionRecipeSummaryResource::collection($recipes),
        ];
    }
}
