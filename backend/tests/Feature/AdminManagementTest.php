<?php

namespace Tests\Feature;

use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class AdminManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_admin_can_search_users_with_bounded_admin_fields(): void
    {
        $admin = $this->createAdmin();
        $user = User::factory()->create(['name' => 'Recipe Owner']);
        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/admin/users?search=Recipe&per_page=1')
            ->assertOk()
            ->assertJsonPath('data.0.id', $user->id)
            ->assertJsonMissingPath('data.0.password');
    }

    public function test_admin_can_suspend_and_reactivate_a_user_with_reason(): void
    {
        $admin = $this->createAdmin();
        $user = User::factory()->create();
        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/users/'.$user->id.'/suspension', [
            'is_suspended' => true,
            'reason' => 'Repeated abusive reports.',
        ])->assertOk()
            ->assertJsonPath('data.is_suspended', true)
            ->assertJsonPath('data.suspension_reason', 'Repeated abusive reports.');

        $this->patchJson('/api/v1/admin/users/'.$user->id.'/suspension', [
            'is_suspended' => false,
        ])->assertOk()
            ->assertJsonPath('data.is_suspended', false)
            ->assertJsonPath('data.suspension_reason', null);
    }

    public function test_admin_recipe_inspection_does_not_return_storage_paths_or_public_image_urls(): void
    {
        $admin = $this->createAdmin();
        $owner = User::factory()->create();
        $recipe = Recipe::create([
            'user_id' => $owner->id,
            'camera_model_id' => $this->createCamera()->id,
            'name' => 'Private archive recipe',
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
        Sanctum::actingAs($admin);

        $this->getJson('/api/v1/admin/recipes/'.$recipe->id)
            ->assertOk()
            ->assertJsonPath('data.status', Recipe::STATUS_PRIVATE)
            ->assertJsonMissingPath('data.images.0.url')
            ->assertJsonMissingPath('data.images.0.original_path');
    }

    public function test_admin_cannot_suspend_their_own_account(): void
    {
        $admin = $this->createAdmin();
        Sanctum::actingAs($admin);

        $this->patchJson('/api/v1/admin/users/'.$admin->id.'/suspension', [
            'is_suspended' => true,
            'reason' => 'Invalid self action',
        ])->assertStatus(422)
            ->assertJsonPath('error.code', 'self_suspension_forbidden');
    }

    private function createCamera(): CameraModel
    {
        return CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20-'.str()->random(6),
        ]);
    }

    private function createAdmin(): User
    {
        $admin = User::factory()->create();
        $admin->forceFill(['is_admin' => true])->save();

        return $admin->fresh();
    }
}
