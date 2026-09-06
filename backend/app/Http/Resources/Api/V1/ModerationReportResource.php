<?php

namespace App\Http\Resources\Api\V1;

use App\Models\ModerationReport;
use App\Models\Recipe;
use App\Models\RecipeComment;
use App\Models\RecipeImage;
use App\Models\User;
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
            'reviewer_note' => $this->resource->getAttribute('reviewer_note'),
            'reporter' => $this->resource->relationLoaded('reporter') && $this->resource->reporter instanceof User ? [
                'id' => $this->resource->reporter->getKey(),
                'name' => $this->resource->reporter->getAttribute('name'),
            ] : null,
            'context' => $this->context(),
            'created_at' => $this->resource->getAttribute('created_at')?->toISOString(),
            'reviewed_at' => $this->resource->getAttribute('reviewed_at')?->toISOString(),
        ];
    }

    private function context(): ?array
    {
        $target = $this->resource->relationLoaded('reportable')
            ? $this->resource->getRelation('reportable')
            : null;

        if ($target instanceof Recipe) {
            return [
                'type' => 'recipe',
                'id' => $target->getKey(),
                'name' => $target->getAttribute('name'),
                'status' => $target->getAttribute('status'),
                'is_hidden' => (bool) $target->getAttribute('is_hidden'),
                'owner' => $target->relationLoaded('user') && $target->user instanceof User ? [
                    'id' => $target->user->getKey(),
                    'name' => $target->user->getAttribute('name'),
                ] : null,
            ];
        }

        if ($target instanceof RecipeComment) {
            return [
                'type' => 'comment',
                'id' => $target->getKey(),
                'body' => $target->getAttribute('body'),
                'is_hidden' => (bool) $target->getAttribute('is_hidden'),
                'author' => $target->relationLoaded('user') && $target->user instanceof User ? [
                    'id' => $target->user->getKey(),
                    'name' => $target->user->getAttribute('name'),
                ] : null,
            ];
        }

        if ($target instanceof RecipeImage) {
            return [
                'type' => 'image',
                'id' => $target->getKey(),
                'mime_type' => $target->getAttribute('mime_type'),
                'width' => $target->getAttribute('width'),
                'height' => $target->getAttribute('height'),
                'recipe' => $target->relationLoaded('recipe') && $target->recipe instanceof Recipe ? [
                    'id' => $target->recipe->getKey(),
                    'name' => $target->recipe->getAttribute('name'),
                ] : null,
            ];
        }

        if ($target instanceof User) {
            return [
                'type' => 'user',
                'id' => $target->getKey(),
                'name' => $target->getAttribute('name'),
                'is_suspended' => (bool) $target->getAttribute('is_suspended'),
            ];
        }

        return null;
    }
}
