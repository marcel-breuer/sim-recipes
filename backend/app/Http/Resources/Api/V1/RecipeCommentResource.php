<?php

namespace App\Http\Resources\Api\V1;

use App\Models\RecipeComment;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin RecipeComment */
class RecipeCommentResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $user = $this->resource->relationLoaded('user')
            ? $this->resource->getRelation('user')
            : null;

        return [
            'id' => $this->resource->getKey(),
            'body' => $this->resource->getAttribute('body'),
            'author' => $user instanceof User ? [
                'id' => $user->getKey(),
                'name' => $user->getAttribute('name'),
            ] : null,
            'can_delete' => $request->user()?->getKey() === $this->resource->getAttribute('user_id'),
            'created_at' => $this->resource->getAttribute('created_at')?->toISOString(),
            'updated_at' => $this->resource->getAttribute('updated_at')?->toISOString(),
        ];
    }
}
