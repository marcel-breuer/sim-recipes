<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\MorphMany;
use Illuminate\Database\Eloquent\SoftDeletes;

class RecipeComment extends Model
{
    use HasUlids, SoftDeletes;

    protected $fillable = [
        'recipe_id',
        'user_id',
        'body',
        'is_hidden',
        'moderated_at',
        'moderation_reason',
    ];

    protected function casts(): array
    {
        return [
            'is_hidden' => 'boolean',
            'moderated_at' => 'datetime',
        ];
    }

    public function recipe(): BelongsTo
    {
        return $this->belongsTo(Recipe::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function moderationReports(): MorphMany
    {
        return $this->morphMany(ModerationReport::class, 'reportable');
    }
}
