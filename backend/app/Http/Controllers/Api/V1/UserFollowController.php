<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Profile;
use App\Models\User;
use App\Models\UserFollow;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\Gate;

class UserFollowController extends Controller
{
    public function store(string $username): JsonResponse
    {
        $target = $this->target($username);
        $this->authorizeFollow($target);

        UserFollow::query()->firstOrCreate([
            'follower_id' => request()->user()->getKey(),
            'followed_id' => $target->getKey(),
        ]);

        return response()->json([
            'data' => [
                'following' => true,
                'followers_count' => $target->followers()->count(),
            ],
        ]);
    }

    public function destroy(string $username): JsonResponse
    {
        $target = $this->target($username);
        $this->authorizeFollow($target);

        UserFollow::query()
            ->where('follower_id', request()->user()->getKey())
            ->where('followed_id', $target->getKey())
            ->delete();

        return response()->json([
            'data' => [
                'following' => false,
                'followers_count' => $target->followers()->count(),
            ],
        ]);
    }

    private function target(string $username): User
    {
        $profile = Profile::query()->where('username', $username)->firstOrFail();

        return User::query()->findOrFail($profile->user_id);
    }

    private function authorizeFollow(User $target): void
    {
        abort_if($target->getKey() === request()->user()->getKey(), 422, 'You cannot follow yourself.');
        abort_unless(Gate::allows('follow', $target), 404);
    }
}
