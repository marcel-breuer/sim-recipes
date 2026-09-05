<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class RecipeImageResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $imageID = $this->resource->getKey();
        $derivatives = $this->resource->getAttribute('derivatives');
        $derivativeURLs = [];
        if (is_array($derivatives)) {
            foreach (['thumbnail', 'detail'] as $variant) {
                if (is_string($derivatives[$variant] ?? null)) {
                    $derivativeURLs[$variant] = route('api.v1.recipe-images.show', [
                        'recipeImage' => $imageID,
                        'variant' => $variant,
                    ]);
                }
            }
        }

        return [
            'id' => $this->resource->getKey(),
            'url' => route('api.v1.recipe-images.show', ['recipeImage' => $imageID]),
            'derivative_urls' => $derivativeURLs,
            'mime_type' => $this->resource->getAttribute('mime_type'),
            'width' => $this->resource->getAttribute('width'),
            'height' => $this->resource->getAttribute('height'),
            'sort_order' => $this->resource->getAttribute('sort_order'),
            'processing_status' => $this->resource->getAttribute('processing_status'),
        ];
    }
}
