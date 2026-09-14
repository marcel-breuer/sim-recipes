<?php

namespace App\Policies;

use App\Models\RecipeCollection;
use App\Models\User;

class RecipeCollectionPolicy
{
    public function manage(User $user, RecipeCollection $collection): bool
    {
        return $collection->user_id === $user->getKey();
    }
}
