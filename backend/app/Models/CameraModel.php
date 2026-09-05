<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

class CameraModel extends Model
{
    use HasUlids;

    protected $fillable = [
        'manufacturer',
        'name',
        'slug',
        'model_identifier',
        'is_supported',
    ];

    protected function casts(): array
    {
        return ['is_supported' => 'boolean'];
    }

    public function capabilities(): HasMany
    {
        return $this->hasMany(CameraCapability::class);
    }

    public function profiles(): HasMany
    {
        return $this->hasMany(Profile::class);
    }

    public function recipes(): HasMany
    {
        return $this->hasMany(Recipe::class);
    }
}
