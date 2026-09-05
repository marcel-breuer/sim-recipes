<?php

namespace App\Services\Recipes;

use App\Models\Recipe;
use Illuminate\Database\Eloquent\Builder;

final class DefaultPopularityRanking implements PopularityRanking
{
    public function apply(Builder $query): void
    {
        $query
            ->orderByRaw('(likes_count * 3 + downloads_count * 5 + views_count) DESC')
            ->orderByDesc('likes_count')
            ->orderByDesc('downloads_count')
            ->orderByDesc('views_count')
            ->orderByDesc('published_at')
            ->orderByDesc('id');
    }

    public function score(Recipe $recipe): int
    {
        return ($recipe->likes_count * 3)
            + ($recipe->downloads_count * 5)
            + $recipe->views_count;
    }
}
