<?php

namespace Tests\Feature;

use App\Models\CameraModel;
use App\Models\Profile;
use App\Models\Recipe;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class ProfileTest extends TestCase
{
    use RefreshDatabase;

    public function test_public_profile_is_readable_without_authentication_and_only_lists_published_recipes(): void
    {
        $user = User::factory()->create(['name' => 'Recipe Author']);
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
        Profile::create([
            'user_id' => $user->id,
            'username' => 'recipe_author',
            'biography' => 'Street photography recipes.',
            'camera_model_id' => $camera->id,
        ]);
        $published = Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $camera->id,
            'name' => 'Published Chrome',
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);
        Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $camera->id,
            'name' => 'Private Draft',
        ]);

        $this->getJson('/api/v1/profiles/recipe_author')
            ->assertOk()
            ->assertJsonPath('data.username', 'recipe_author')
            ->assertJsonPath('data.display_name', 'Recipe Author')
            ->assertJsonPath('data.camera_model.slug', 'x-s20')
            ->assertJsonPath('data.published_recipes.0.id', $published->id)
            ->assertJsonMissing(['name' => 'Private Draft']);
    }

    public function test_authenticated_owner_can_create_and_update_their_profile_and_unset_optional_fields(): void
    {
        $user = User::factory()->create();
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
        Sanctum::actingAs($user);

        $this->patchJson('/api/v1/me/profile', [
            'username' => 'new_profile',
            'camera_model_id' => $camera->id,
            'biography' => 'A short bio.',
        ])->assertOk()
            ->assertJsonPath('data.username', 'new_profile');

        $this->patchJson('/api/v1/me/profile', [
            'camera_model_id' => null,
            'biography' => null,
        ])->assertOk()
            ->assertJsonPath('data.camera_model', null)
            ->assertJsonPath('data.biography', null);

        $this->assertDatabaseHas('profiles', [
            'user_id' => $user->id,
            'username' => 'new_profile',
            'camera_model_id' => null,
            'biography' => null,
        ]);
    }

    public function test_profile_updates_require_authentication_and_validate_username_and_image_size(): void
    {
        $this->patchJson('/api/v1/me/profile', ['username' => 'anonymous'])
            ->assertUnauthorized();

        $user = User::factory()->create();
        Sanctum::actingAs($user);
        Storage::fake('local');
        config(['filesystems.default' => 'local']);

        $this->post('/api/v1/me/profile', [
            'username' => 'Invalid Name',
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');

        $this->post('/api/v1/me/profile', [
            'username' => 'valid_name',
            'profile_image' => UploadedFile::fake()->create('profile.jpg', 5121, 'image/jpeg'),
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');
    }
}
