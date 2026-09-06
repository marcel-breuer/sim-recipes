<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Profile;
use App\Models\User;
use App\Models\UserBlock;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;

class UserSafetyController extends Controller
{
    public function block(Request $request, string $username): JsonResponse
    {
        $target = $this->target($username);
        $user = $request->user();
        abort_if($target->getKey() === $user->getKey(), 422, 'You cannot block yourself.');

        UserBlock::query()->firstOrCreate([
            'blocker_id' => $user->getKey(),
            'blocked_user_id' => $target->getKey(),
        ]);

        return response()->json(['data' => ['blocked' => true]]);
    }

    public function unblock(Request $request, string $username): JsonResponse
    {
        $target = $this->target($username);
        UserBlock::query()
            ->where('blocker_id', $request->user()->getKey())
            ->where('blocked_user_id', $target->getKey())
            ->delete();

        return response()->json(['data' => ['blocked' => false]]);
    }

    public function blockUser(Request $request, User $user): JsonResponse
    {
        return $this->createBlock($request, $user);
    }

    public function unblockUser(Request $request, User $user): JsonResponse
    {
        return $this->removeBlock($request, $user);
    }

    private function target(string $username): User
    {
        $profile = Profile::query()->where('username', $username)->firstOrFail();

        return User::query()->findOrFail($profile->user_id);
    }

    private function createBlock(Request $request, User $target): JsonResponse
    {
        abort_if($target->getKey() === $request->user()->getKey(), 422, 'You cannot block yourself.');

        UserBlock::query()->firstOrCreate([
            'blocker_id' => $request->user()->getKey(),
            'blocked_user_id' => $target->getKey(),
        ]);

        return response()->json(['data' => ['blocked' => true]]);
    }

    private function removeBlock(Request $request, User $target): JsonResponse
    {
        UserBlock::query()
            ->where('blocker_id', $request->user()->getKey())
            ->where('blocked_user_id', $target->getKey())
            ->delete();

        return response()->json(['data' => ['blocked' => false]]);
    }
}
