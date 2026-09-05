<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class RecipeSettingResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'key' => $this->resource->getAttribute('setting_key'),
            'value' => $this->resource->getAttribute('value'),
        ];
    }
}
