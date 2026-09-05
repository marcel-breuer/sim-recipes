<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class RecipeImage extends Model
{
    use HasUlids;

    protected $fillable = [
        'recipe_id',
        'storage_disk',
        'original_path',
        'original_size_bytes',
        'mime_type',
        'width',
        'height',
        'sort_order',
        'derivatives',
        'processing_status',
    ];

    protected function casts(): array
    {
        return [
            'original_size_bytes' => 'integer',
            'width' => 'integer',
            'height' => 'integer',
            'sort_order' => 'integer',
            'derivatives' => 'array',
        ];
    }

    public function recipe(): BelongsTo
    {
        return $this->belongsTo(Recipe::class);
    }
}
