<?php

namespace App\Services\Admin;

use App\Models\AdminAuditLog;
use App\Models\User;
use Illuminate\Database\Eloquent\Model;

class AdminAuditLogger
{
    private const SAFE_METADATA_KEYS = [
        'previous_is_suspended',
        'is_suspended',
        'previous_status',
        'status',
        'resolution',
    ];

    /** @param array<string, mixed> $metadata */
    public function record(
        User $actor,
        string $action,
        ?Model $target,
        ?string $reason,
        string $outcome,
        array $metadata = [],
    ): AdminAuditLog {
        $safeMetadata = [];
        foreach (self::SAFE_METADATA_KEYS as $key) {
            if (! array_key_exists($key, $metadata)) {
                continue;
            }

            $value = $metadata[$key];
            if (is_scalar($value) || $value === null) {
                $safeMetadata[$key] = $value;
            }
        }

        return AdminAuditLog::create([
            'actor_id' => $actor->getKey(),
            'action' => $action,
            'target_type' => $target?->getMorphClass(),
            'target_id' => $target?->getKey(),
            'reason' => $reason,
            'outcome' => $outcome,
            'metadata' => $safeMetadata === [] ? null : $safeMetadata,
        ]);
    }
}
