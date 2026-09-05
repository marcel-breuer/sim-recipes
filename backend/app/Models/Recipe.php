<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Database\Eloquent\Relations\HasOne;
use Illuminate\Database\Eloquent\Relations\MorphMany;

class Recipe extends Model
{
    use HasUlids;

    public const STATUS_PRIVATE = 'private';

    public const STATUS_PUBLISHED = 'published';

    protected $fillable = [
        'user_id',
        'camera_model_id',
        'name',
        'description',
        'recommendation',
        'lens',
        'status',
        'is_hidden',
        'moderated_at',
        'moderation_reason',
        'published_at',
        'views_count',
        'likes_count',
        'downloads_count',
    ];

    protected function casts(): array
    {
        return [
            'published_at' => 'datetime',
            'is_hidden' => 'boolean',
            'moderated_at' => 'datetime',
            'views_count' => 'integer',
            'likes_count' => 'integer',
            'downloads_count' => 'integer',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function cameraModel(): BelongsTo
    {
        return $this->belongsTo(CameraModel::class);
    }

    public function settings(): HasMany
    {
        return $this->hasMany(RecipeSetting::class);
    }

    public function images(): HasMany
    {
        return $this->hasMany(RecipeImage::class)->orderBy('sort_order');
    }

    public function categories(): BelongsToMany
    {
        return $this->belongsToMany(Category::class);
    }

    public function tags(): BelongsToMany
    {
        return $this->belongsToMany(Tag::class);
    }

    public function likes(): HasMany
    {
        return $this->hasMany(Like::class);
    }

    public function views(): HasMany
    {
        return $this->hasMany(RecipeView::class);
    }

    public function downloads(): HasMany
    {
        return $this->hasMany(RecipeDownload::class);
    }

    public function provenance(): HasOne
    {
        return $this->hasOne(RecipeProvenance::class, 'copied_recipe_id');
    }

    public function moderationReports(): MorphMany
    {
        return $this->morphMany(ModerationReport::class, 'reportable');
    }
}
