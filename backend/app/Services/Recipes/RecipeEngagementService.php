<?php

namespace App\Services\Recipes;

use App\Models\Like;
use App\Models\Recipe;
use App\Models\RecipeDownload;
use App\Models\RecipeView;
use App\Models\User;
use Illuminate\Support\Facades\DB;

final class RecipeEngagementService
{
    public const VIEW_DEDUPLICATION_MINUTES = 15;

    public function like(User $user, Recipe $recipe): bool
    {
        return DB::transaction(function () use ($user, $recipe): bool {
            $like = Like::query()->firstOrCreate([
                'user_id' => $user->getKey(),
                'recipe_id' => $recipe->getKey(),
            ]);

            if (! $like->wasRecentlyCreated) {
                return false;
            }

            Recipe::query()->whereKey($recipe->getKey())->increment('likes_count');

            return true;
        });
    }

    public function unlike(User $user, Recipe $recipe): bool
    {
        return DB::transaction(function () use ($user, $recipe): bool {
            $deleted = Like::query()
                ->where('user_id', $user->getKey())
                ->where('recipe_id', $recipe->getKey())
                ->delete();

            if ($deleted === 0) {
                return false;
            }

            Recipe::query()
                ->whereKey($recipe->getKey())
                ->where('likes_count', '>', 0)
                ->decrement('likes_count');

            return true;
        });
    }

    public function recordView(Recipe $recipe, ?User $viewer, string $anonymousKey): bool
    {
        return DB::transaction(function () use ($recipe, $viewer, $anonymousKey): bool {
            $recentViews = RecipeView::query()
                ->where('recipe_id', $recipe->getKey())
                ->where('viewed_at', '>=', now()->subMinutes(self::VIEW_DEDUPLICATION_MINUTES));

            if ($viewer !== null) {
                $recentViews->where('viewer_id', $viewer->getKey());
            } else {
                $recentViews
                    ->whereNull('viewer_id')
                    ->where('anonymous_key', $anonymousKey);
            }

            if ($recentViews->exists()) {
                return false;
            }

            RecipeView::create([
                'recipe_id' => $recipe->getKey(),
                'viewer_id' => $viewer?->getKey(),
                'anonymous_key' => $viewer === null ? $anonymousKey : null,
                'viewed_at' => now(),
            ]);
            Recipe::query()->whereKey($recipe->getKey())->increment('views_count');

            return true;
        });
    }

    public function recordDownload(Recipe $sourceRecipe, User $user, ?Recipe $copiedRecipe = null): RecipeDownload
    {
        $download = RecipeDownload::create([
            'recipe_id' => $sourceRecipe->getKey(),
            'user_id' => $user->getKey(),
            'copied_recipe_id' => $copiedRecipe?->getKey(),
        ]);
        Recipe::query()->whereKey($sourceRecipe->getKey())->increment('downloads_count');

        return $download;
    }
}
