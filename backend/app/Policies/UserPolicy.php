<?php

namespace App\Policies;

use App\Models\User;
use App\Models\UserBlock;

class UserPolicy
{
    public function follow(User $user, User $target): bool
    {
        if ($user->getKey() === $target->getKey() || $target->is_suspended) {
            return false;
        }

        return ! UserBlock::query()
            ->where(function ($query) use ($user, $target): void {
                $query
                    ->where('blocker_id', $user->getKey())
                    ->where('blocked_user_id', $target->getKey());
            })
            ->orWhere(function ($query) use ($user, $target): void {
                $query
                    ->where('blocker_id', $target->getKey())
                    ->where('blocked_user_id', $user->getKey());
            })
            ->exists();
    }
}
