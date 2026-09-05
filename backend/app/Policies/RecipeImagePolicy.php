<?php

namespace App\Policies;

use App\Models\Recipe;
use App\Models\RecipeImage;
use App\Models\User;

class RecipeImagePolicy
{
    public function view(?User $user, RecipeImage $image): bool
    {
        $recipe = $this->recipeFor($image);

        return $recipe->status === Recipe::STATUS_PUBLISHED
            || ($user !== null && $recipe->user_id === $user->getKey());
    }

    public function delete(User $user, RecipeImage $image): bool
    {
        $recipe = $this->recipeFor($image);

        return $recipe->status === Recipe::STATUS_PRIVATE
            && $recipe->user_id === $user->getKey();
    }

    private function recipeFor(RecipeImage $image): Recipe
    {
        return Recipe::query()->findOrFail($image->getAttribute('recipe_id'));
    }
}
