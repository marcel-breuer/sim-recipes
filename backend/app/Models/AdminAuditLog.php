<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Concerns\HasUlids;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

class AdminAuditLog extends Model
{
    use HasUlids;

    protected $fillable = [
        'actor_id',
        'action',
        'target_type',
        'target_id',
        'reason',
        'outcome',
        'metadata',
    ];

    protected function casts(): array
    {
        return ['metadata' => 'array'];
    }

    protected static function booted(): void
    {
        static::updating(static function (): void {
            throw new \LogicException('Admin audit logs are append-only.');
        });
        static::deleting(static function (): void {
            throw new \LogicException('Admin audit logs are append-only.');
        });
    }

    public function actor(): BelongsTo
    {
        return $this->belongsTo(User::class, 'actor_id');
    }
}
