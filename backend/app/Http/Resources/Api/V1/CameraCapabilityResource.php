<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

class CameraCapabilityResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->getKey(),
            'key' => $this->resource->getAttribute('setting_key'),
            'display_name' => $this->resource->getAttribute('display_name'),
            'value_type' => $this->resource->getAttribute('value_type'),
            'allowed_values' => $this->resource->getAttribute('allowed_values'),
            'minimum' => $this->resource->getAttribute('minimum'),
            'maximum' => $this->resource->getAttribute('maximum'),
            'step' => $this->resource->getAttribute('step'),
            'transport_identifier' => $this->resource->getAttribute('transport_identifier'),
            'custom_slot_metadata' => $this->resource->getAttribute('custom_slot_metadata'),
            'evidence' => [
                'level' => $this->resource->getAttribute('evidence_level'),
                'source' => $this->resource->getAttribute('evidence_source'),
                'firmware' => $this->resource->getAttribute('verified_firmware'),
                'verified_at' => $this->resource->getAttribute('verified_at')?->toIso8601String(),
            ],
        ];
    }
}
