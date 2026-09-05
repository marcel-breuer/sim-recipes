<?php

namespace Tests\Feature;

use App\Models\CameraCapability;
use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RecipeLifecycleTest extends TestCase
{
    use RefreshDatabase;

    public function test_private_recipes_are_owner_only_and_owner_can_update_and_delete_them(): void
    {
        $owner = User::factory()->create();
        $otherUser = User::factory()->create();
        $camera = $this->createCamera();

        Sanctum::actingAs($owner);
        $response = $this->postJson('/api/v1/recipes', [
            'name' => 'Private Chrome',
            'camera_model_id' => $camera->id,
        ])->assertOk()
            ->assertJsonPath('data.status', Recipe::STATUS_PRIVATE);

        $recipeID = $response->json('data.id');

        Sanctum::actingAs($otherUser);
        $this->getJson('/api/v1/recipes/'.$recipeID)->assertNotFound();

        Sanctum::actingAs($owner);
        $this->patchJson('/api/v1/recipes/'.$recipeID, [
            'name' => 'Updated Chrome',
            'description' => null,
        ])->assertOk()
            ->assertJsonPath('data.name', 'Updated Chrome')
            ->assertJsonPath('data.description', null);

        $this->deleteJson('/api/v1/recipes/'.$recipeID)
            ->assertOk()
            ->assertJsonPath('data.deleted', true);

        $this->assertDatabaseMissing('recipes', ['id' => $recipeID]);
    }

    public function test_incompatible_camera_settings_are_rejected(): void
    {
        $user = User::factory()->create();
        $camera = $this->createCamera();
        CameraCapability::create([
            'camera_model_id' => $camera->id,
            'setting_key' => 'film_simulation',
            'display_name' => 'Film Simulation',
            'value_type' => 'enum',
            'allowed_values' => ['Classic Chrome'],
            'transport_identifier' => 'film_simulation',
        ]);

        Sanctum::actingAs($user);
        $this->postJson('/api/v1/recipes', [
            'name' => 'Unsupported Recipe',
            'camera_model_id' => $camera->id,
            'settings' => [[
                'setting_key' => 'film_simulation',
                'value' => 'Unsupported',
            ]],
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');

        $this->assertDatabaseMissing('recipes', ['name' => 'Unsupported Recipe']);
    }

    public function test_publication_requires_an_image_and_published_recipes_are_immutable(): void
    {
        Storage::fake('local');
        config(['filesystems.default' => 'local']);

        $owner = User::factory()->create();
        $otherUser = User::factory()->create();
        $camera = $this->createCamera();

        Sanctum::actingAs($owner);
        $draft = $this->postJson('/api/v1/recipes', [
            'name' => 'Missing Image',
            'camera_model_id' => $camera->id,
        ])->assertOk();
        $this->postJson('/api/v1/recipes/'.$draft->json('data.id').'/publish')
            ->assertUnprocessable();

        $response = $this->post('/api/v1/recipes', [
            'name' => 'Published Chrome',
            'camera_model_id' => $camera->id,
            'images' => [UploadedFile::fake()->image('recipe.jpg')],
        ])->assertOk();
        $recipeID = $response->json('data.id');

        $this->postJson('/api/v1/recipes/'.$recipeID.'/publish')
            ->assertOk()
            ->assertJsonPath('data.status', Recipe::STATUS_PUBLISHED);

        Sanctum::actingAs($otherUser);
        $this->getJson('/api/v1/recipes/'.$recipeID)
            ->assertOk()
            ->assertJsonPath('data.name', 'Published Chrome');

        Sanctum::actingAs($owner);
        $this->patchJson('/api/v1/recipes/'.$recipeID, ['name' => 'Changed After Publish'])
            ->assertForbidden();
        $this->deleteJson('/api/v1/recipes/'.$recipeID)->assertForbidden();

        $this->assertDatabaseHas('recipes', [
            'id' => $recipeID,
            'status' => Recipe::STATUS_PUBLISHED,
        ]);
    }

    private function createCamera(): CameraModel
    {
        return CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
    }
}
