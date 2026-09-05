<?php

namespace App\Services\Recipes;

use App\Models\Recipe;
use Illuminate\Database\Eloquent\Builder;

interface PopularityRanking
{
    /**
     * @param  Builder<Recipe>  $query
     */
    public function apply(Builder $query): void;
}
