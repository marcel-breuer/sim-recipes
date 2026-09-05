<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Storage;

class RecipeImageResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $disk = $this->resource->getAttribute('storage_disk');
        $path = $this->resource->getAttribute('original_path');

        return [
            'id' => $this->resource->getKey(),
            'url' => Storage::disk($disk)->url($path),
            'mime_type' => $this->resource->getAttribute('mime_type'),
            'width' => $this->resource->getAttribute('width'),
            'height' => $this->resource->getAttribute('height'),
            'sort_order' => $this->resource->getAttribute('sort_order'),
        ];
    }
}
