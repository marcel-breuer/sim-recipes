<?php

namespace Tests\Feature;

use App\Models\CameraModel;
use App\Models\ModerationReport;
use App\Models\Profile;
use App\Models\Recipe;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ModerationTest extends TestCase
{
    use RefreshDatabase;

    public function test_objectionable_recipe_text_is_rejected_before_storage(): void
    {
        $user = User::factory()->create();
        $camera = $this->createCamera();
        Sanctum::actingAs($user);

        $this->postJson('/api/v1/recipes', [
            'name' => 'Porn recipe',
            'camera_model_id' => $camera->id,
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');

        $this->assertDatabaseMissing('recipes', ['name' => 'Porn recipe']);
    }

    public function test_objectionable_recipe_text_is_rejected_before_publication(): void
    {
        $user = User::factory()->create();
        $recipe = Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $this->createCamera()->id,
            'name' => 'Porn recipe',
            'status' => Recipe::STATUS_PRIVATE,
        ]);
        $recipe->images()->create([
            'storage_disk' => 'local',
            'original_path' => 'recipes/'.$recipe->id.'/original.jpg',
            'original_size_bytes' => 1024,
            'mime_type' => 'image/jpeg',
            'sort_order' => 0,
            'processing_status' => 'ready',
        ]);

        Sanctum::actingAs($user);

        $this->postJson('/api/v1/recipes/'.$recipe->id.'/publish')
            ->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');

        $this->assertDatabaseHas('recipes', [
            'id' => $recipe->id,
            'status' => Recipe::STATUS_PRIVATE,
            'published_at' => null,
        ]);
    }

    public function test_user_can_report_recipe_and_admin_can_hide_it(): void
    {
        $author = User::factory()->create();
        $reporter = User::factory()->create();
        $admin = User::factory()->create();
        $admin->forceFill(['is_admin' => true])->save();
        $recipe = Recipe::create([
            'user_id' => $author->id,
            'camera_model_id' => $this->createCamera()->id,
            'name' => 'Reported recipe',
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);

        Sanctum::actingAs($reporter);
        $report = $this->postJson('/api/v1/recipes/'.$recipe->id.'/reports', [
            'reason' => 'objectionable_content',
            'details' => 'Please review this recipe.',
        ])->assertCreated()
            ->assertJsonPath('data.status', 'open');

        Sanctum::actingAs($admin);
        $this->getJson('/api/v1/admin/reports')
            ->assertOk()
            ->assertJsonPath('data.0.id', $report->json('data.id'));

        $this->patchJson('/api/v1/admin/reports/'.$report->json('data.id'), [
            'status' => 'resolved',
            'resolution' => 'hide_content',
        ])->assertOk()
            ->assertJsonPath('data.status', 'resolved');

        $this->assertDatabaseHas('recipes', ['id' => $recipe->id, 'is_hidden' => true]);
        $this->getJson('/api/v1/recipes/'.$recipe->id)->assertNotFound();
    }

    public function test_non_admin_cannot_discover_admin_report_endpoints(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $this->getJson('/api/v1/admin/reports')->assertNotFound();
        $this->patchJson('/api/v1/admin/reports/'.str()->ulid(), [
            'status' => 'resolved',
        ])->assertNotFound();
    }

    public function test_blocked_profile_and_public_recipes_are_hidden_from_blocker(): void
    {
        $author = User::factory()->create();
        $blocker = User::factory()->create();
        Profile::create(['user_id' => $author->id, 'username' => 'blocked-author']);
        $recipe = Recipe::create([
            'user_id' => $author->id,
            'camera_model_id' => $this->createCamera()->id,
            'name' => 'Blocked recipe',
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);

        Sanctum::actingAs($blocker);
        $this->postJson('/api/v1/profiles/blocked-author/block')
            ->assertOk()
            ->assertJsonPath('data.blocked', true);

        $this->getJson('/api/v1/profiles/blocked-author')->assertNotFound();
        $this->getJson('/api/v1/recipes/'.$recipe->id)->assertNotFound();
        $this->getJson('/api/v1/recipes')->assertJsonCount(0, 'data');

        $this->deleteJson('/api/v1/profiles/blocked-author/block')
            ->assertOk()
            ->assertJsonPath('data.blocked', false);
        $this->getJson('/api/v1/recipes/'.$recipe->id)->assertOk();
    }

    public function test_admin_report_queue_returns_context_and_supports_filters(): void
    {
        $author = User::factory()->create();
        $reporter = User::factory()->create();
        $admin = User::factory()->create();
        $admin->forceFill(['is_admin' => true])->save();
        $recipe = Recipe::create([
            'user_id' => $author->id,
            'camera_model_id' => $this->createCamera()->id,
            'name' => 'Queue context recipe',
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);

        Sanctum::actingAs($reporter);
        $this->postJson('/api/v1/recipes/'.$recipe->id.'/reports', [
            'reason' => 'spam',
        ])->assertCreated();

        Sanctum::actingAs($admin);
        $this->getJson('/api/v1/admin/reports?reason=spam&reportable_type=Recipe')
            ->assertOk()
            ->assertJsonPath('data.0.context.type', 'recipe')
            ->assertJsonPath('data.0.context.name', 'Queue context recipe')
            ->assertJsonPath('data.0.reporter.id', $reporter->id);
    }

    public function test_resolving_a_report_is_idempotent(): void
    {
        $author = User::factory()->create();
        $reporter = User::factory()->create();
        $admin = User::factory()->create();
        $admin->forceFill(['is_admin' => true])->save();
        $recipe = Recipe::create([
            'user_id' => $author->id,
            'camera_model_id' => $this->createCamera()->id,
            'name' => 'Idempotent report recipe',
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);

        Sanctum::actingAs($reporter);
        $report = $this->postJson('/api/v1/recipes/'.$recipe->id.'/reports', [
            'reason' => 'objectionable_content',
        ])->json('data.id');

        Sanctum::actingAs($admin);
        $payload = ['status' => 'resolved', 'resolution' => 'hide_content', 'reviewer_note' => 'Hidden.'];
        $this->patchJson('/api/v1/admin/reports/'.$report, $payload)->assertOk();
        $firstReviewedAt = ModerationReport::query()->findOrFail($report)->reviewed_at;
        $this->patchJson('/api/v1/admin/reports/'.$report, $payload)
            ->assertOk()
            ->assertJsonPath('data.reviewer_note', 'Hidden.');
        $this->assertEquals($firstReviewedAt?->toISOString(), ModerationReport::query()->findOrFail($report)->reviewed_at?->toISOString());
    }

    private function createCamera(): CameraModel
    {
        return CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20-'.str()->random(6),
        ]);
    }
}
