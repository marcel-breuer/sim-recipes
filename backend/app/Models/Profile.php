<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class Profile extends Model
{
    use HasUlids;

    protected $fillable = [
        'user_id',
        'username',
        'profile_image_path',
        'camera_model_id',
        'biography',
    ];

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function cameraModel(): BelongsTo
    {
        return $this->belongsTo(CameraModel::class);
    }
}
