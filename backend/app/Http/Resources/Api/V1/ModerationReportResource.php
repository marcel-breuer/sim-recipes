<?php

namespace App\Http\Resources\Api\V1;

use App\Models\ModerationReport;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin ModerationReport */
class ModerationReportResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        return [
            'id' => $this->resource->getKey(),
            'reportable_type' => class_basename((string) $this->resource->getAttribute('reportable_type')),
            'reportable_id' => $this->resource->getAttribute('reportable_id'),
            'reason' => $this->resource->getAttribute('reason'),
            'details' => $this->resource->getAttribute('details'),
            'status' => $this->resource->getAttribute('status'),
            'resolution' => $this->resource->getAttribute('resolution'),
            'created_at' => $this->resource->getAttribute('created_at')?->toISOString(),
            'reviewed_at' => $this->resource->getAttribute('reviewed_at')?->toISOString(),
        ];
    }
}
