<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Admin\AdminAuditLogger;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class AdminAuditTest extends TestCase
{
    use RefreshDatabase;

    public function test_audit_logger_records_actor_action_target_reason_outcome_and_safe_metadata(): void
    {
        $actor = $this->createAdmin();
        $target = User::factory()->create();

        $log = app(AdminAuditLogger::class)->record(
            $actor,
            'user.suspension.update',
            $target,
            'Repeated abusive reports.',
            'succeeded',
            [
                'previous_is_suspended' => false,
                'is_suspended' => true,
                'authorization_header' => 'must-not-be-stored',
            ],
        );

        $this->assertDatabaseHas('admin_audit_logs', [
            'id' => $log->id,
            'actor_id' => $actor->id,
            'action' => 'user.suspension.update',
            'target_type' => User::class,
            'target_id' => $target->id,
            'reason' => 'Repeated abusive reports.',
            'outcome' => 'succeeded',
        ]);
        $this->assertEqualsCanonicalizing([
            'previous_is_suspended' => false,
            'is_suspended' => true,
        ], $log->fresh()->metadata);
    }

    public function test_audit_logs_are_append_only_and_have_no_public_endpoint(): void
    {
        $actor = $this->createAdmin();
        $log = app(AdminAuditLogger::class)->record(
            $actor,
            'test.action',
            null,
            null,
            'succeeded',
        );

        $this->expectException(\LogicException::class);
        $log->update(['outcome' => 'changed']);
    }

    public function test_non_admin_cannot_access_audit_log_data(): void
    {
        $user = User::factory()->create();

        $this->actingAs($user, 'sanctum');
        $this->getJson('/api/v1/admin/audit-logs')->assertNotFound();
    }

    private function createAdmin(): User
    {
        $admin = User::factory()->create();
        $admin->forceFill(['is_admin' => true])->save();

        return $admin->fresh();
    }
}
