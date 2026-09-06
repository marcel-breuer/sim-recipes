<?php

namespace App\Policies;

use App\Models\Recipe;
use App\Models\User;

class RecipePolicy
{
    public function view(?User $user, Recipe $recipe): bool
    {
        if ($recipe->is_hidden || $recipe->user()->where('is_suspended', true)->exists()) {
            return false;
        }

        return ($user === null || ! $user->blocksCreated()->where('blocked_user_id', $recipe->user_id)->exists())
            && ($recipe->status === Recipe::STATUS_PUBLISHED
                || ($user !== null && $recipe->user_id === $user->getKey()));
    }

    public function update(User $user, Recipe $recipe): bool
    {
        return $recipe->status === Recipe::STATUS_PRIVATE
            && $recipe->user_id === $user->getKey();
    }

    public function delete(User $user, Recipe $recipe): bool
    {
        return $this->update($user, $recipe);
    }

    public function publish(User $user, Recipe $recipe): bool
    {
        return $this->update($user, $recipe);
    }
}
