<?php

namespace App\Http\Resources\Api\V1;

use App\Models\CameraModel;
use App\Models\User;
use App\Models\UserFollow;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Facades\Storage;

class ProfileResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $cameraModel = $this->resource->relationLoaded('cameraModel')
            ? $this->resource->getRelation('cameraModel')
            : null;
        $user = $this->resource->relationLoaded('user')
            ? $this->resource->getRelation('user')
            : null;
        $publishedRecipes = $user instanceof User && $user->relationLoaded('publishedRecipes')
            ? $user->getRelation('publishedRecipes')
            : [];
        $isFollowing = $user instanceof User && $request->user() !== null
            ? UserFollow::query()
                ->where('follower_id', $request->user()->getKey())
                ->where('followed_id', $user->getKey())
                ->exists()
            : false;
        $profileImagePath = $this->resource->getAttribute('profile_image_path');

        return [
            'id' => $this->resource->getKey(),
            'username' => $this->resource->getAttribute('username'),
            'display_name' => $user instanceof User ? $user->getAttribute('name') : null,
            'biography' => $this->resource->getAttribute('biography'),
            'camera_model' => $cameraModel instanceof CameraModel ? [
                'id' => $cameraModel->getKey(),
                'name' => $cameraModel->getAttribute('name'),
                'slug' => $cameraModel->getAttribute('slug'),
            ] : null,
            'profile_image_url' => ! is_string($profileImagePath)
                ? null
                : Storage::disk()->url($profileImagePath),
            'published_recipes' => PublishedRecipeSummaryResource::collection($publishedRecipes),
            'followers_count' => $user instanceof User ? (int) ($user->getAttribute('followers_count') ?? 0) : 0,
            'following_count' => $user instanceof User ? (int) ($user->getAttribute('following_count') ?? 0) : 0,
            'is_following' => $isFollowing,
        ];
    }
}
