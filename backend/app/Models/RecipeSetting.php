<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class RecipeSetting extends Model
{
    use HasUlids;

    protected $fillable = [
        'recipe_id',
        'camera_capability_id',
        'setting_key',
        'value',
    ];

    protected function casts(): array
    {
        return ['value' => 'array'];
    }

    public function recipe(): BelongsTo
    {
        return $this->belongsTo(Recipe::class);
    }

    public function cameraCapability(): BelongsTo
    {
        return $this->belongsTo(CameraCapability::class);
    }
}
