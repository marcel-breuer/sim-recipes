<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

class CameraCapability extends Model
{
    use HasUlids;

    protected $fillable = [
        'camera_model_id',
        'setting_key',
        'display_name',
        'value_type',
        'allowed_values',
        'minimum',
        'maximum',
        'step',
        'transport_identifier',
        'custom_slot_metadata',
    ];

    protected function casts(): array
    {
        return [
            'allowed_values' => 'array',
            'custom_slot_metadata' => 'array',
            'minimum' => 'float',
            'maximum' => 'float',
            'step' => 'float',
        ];
    }

    public function cameraModel(): BelongsTo
    {
        return $this->belongsTo(CameraModel::class);
    }

    public function recipeSettings(): HasMany
    {
        return $this->hasMany(RecipeSetting::class);
    }
}
