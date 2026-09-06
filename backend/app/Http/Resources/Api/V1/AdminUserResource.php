<?php

namespace App\Http\Resources\Api\V1;

use App\Models\Profile;
use App\Models\User;
use Carbon\CarbonInterface;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;

/** @mixin User */
class AdminUserResource extends JsonResource
{
    public function toArray(Request $request): array
    {
        $profile = $this->resource->relationLoaded('profile')
            ? $this->resource->getRelation('profile')
            : null;
        $suspendedAt = $this->resource->getAttribute('suspended_at');

        return [
            'id' => $this->resource->getKey(),
            'name' => $this->resource->getAttribute('name'),
            'email' => $this->resource->getAttribute('email'),
            'is_admin' => (bool) $this->resource->getAttribute('is_admin'),
            'is_suspended' => (bool) $this->resource->getAttribute('is_suspended'),
            'suspended_at' => $suspendedAt instanceof CarbonInterface ? $suspendedAt->toISOString() : null,
            'suspension_reason' => $this->resource->getAttribute('suspension_reason'),
            'created_at' => $this->resource->getAttribute('created_at')?->toISOString(),
            'recipe_count' => (int) ($this->resource->getAttribute('recipes_count') ?? 0),
            'published_recipe_count' => (int) ($this->resource->getAttribute('published_recipes_count') ?? 0),
            'profile' => $profile instanceof Profile ? [
                'username' => $profile->getAttribute('username'),
                'biography' => $profile->getAttribute('biography'),
            ] : null,
        ];
    }
}
