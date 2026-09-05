<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class RecipeDownload extends Model
{
    use HasUlids;

    public const UPDATED_AT = null;

    protected $fillable = ['recipe_id', 'user_id', 'copied_recipe_id', 'created_at'];

    protected function casts(): array
    {
        return ['created_at' => 'datetime'];
    }

    public function recipe(): BelongsTo
    {
        return $this->belongsTo(Recipe::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function copiedRecipe(): BelongsTo
    {
        return $this->belongsTo(Recipe::class, 'copied_recipe_id');
    }
}
