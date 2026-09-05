<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class RecipeProvenance extends Model
{
    use HasUlids;

    protected $fillable = [
        'copied_recipe_id',
        'source_recipe_id',
        'source_author_id',
        'copied_by_user_id',
    ];

    public function copiedRecipe(): BelongsTo
    {
        return $this->belongsTo(Recipe::class, 'copied_recipe_id');
    }

    public function sourceRecipe(): BelongsTo
    {
        return $this->belongsTo(Recipe::class, 'source_recipe_id');
    }

    public function sourceAuthor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'source_author_id');
    }

    public function copiedByUser(): BelongsTo
    {
        return $this->belongsTo(User::class, 'copied_by_user_id');
    }
}
