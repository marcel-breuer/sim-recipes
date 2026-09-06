<?php

namespace App\Policies;

use App\Models\RecipeComment;
use App\Models\User;

class RecipeCommentPolicy
{
    public function delete(User $user, RecipeComment $comment): bool
    {
        return $comment->user_id === $user->getKey();
    }
}
