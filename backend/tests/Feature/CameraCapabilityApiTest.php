<?php

namespace Tests\Feature;

use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\User;
use Database\Seeders\CameraCapabilitySeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class CameraCapabilityApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_supported_cameras_and_capabilities_are_publicly_readable(): void
    {
        $this->seed(CameraCapabilitySeeder::class);

        $camera = CameraModel::query()->where('slug', 'fujifilm-x-s20')->firstOrFail();

        $this->getJson('/api/v1/cameras')
            ->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.slug', 'fujifilm-x-s20')
            ->assertJsonCount(15, 'data.0.capabilities')
            ->assertJsonPath('data.1.slug', 'fujifilm-x-t5')
            ->assertJsonPath('data.1.unsupported_recipe_settings.0', 'monochromatic_color')
            ->assertJsonFragment([
                'key' => 'film_simulation',
                'display_name' => 'Film Simulation',
            ]);

        $this->getJson('/api/v1/cameras/'.$camera->id)
            ->assertOk()
            ->assertJsonPath('data.model_identifier', 'X-S20')
            ->assertJsonCount(15, 'data.capabilities');

        $xT5 = CameraModel::query()->where('slug', 'fujifilm-x-t5')->firstOrFail();

        $this->getJson('/api/v1/cameras/'.$xT5->id)
            ->assertOk()
            ->assertJsonPath('data.model_identifier', 'X-T5')
            ->assertJsonPath('data.transport_metadata.property_reads', 'unverified')
            ->assertJsonCount(15, 'data.capabilities');

        $this->getJson('/api/v1/cameras/fujifilm-x-s20/capabilities')
            ->assertOk()
            ->assertJsonCount(15, 'data')
            ->assertJsonFragment([
                'key' => 'dynamic_range',
                'allowed_values' => ['AUTO', '100%', '200%', '400%'],
            ]);

        $this->getJson('/api/v1/cameras/fujifilm-x-t5/capabilities')
            ->assertOk()
            ->assertJsonCount(15, 'data')
            ->assertJsonFragment([
                'key' => 'iso',
                'minimum' => 64,
                'maximum' => 51200,
            ]);
    }

    public function test_unsupported_cameras_are_not_exposed(): void
    {
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'Unsupported Camera',
            'slug' => 'unsupported-camera',
            'is_supported' => false,
        ]);

        $this->getJson('/api/v1/cameras/'.$camera->id)->assertNotFound();
        $this->getJson('/api/v1/cameras/unsupported-camera/capabilities')->assertNotFound();
    }

    public function test_recipe_settings_accept_valid_capabilities_and_reject_invalid_or_unsupported_values(): void
    {
        $this->seed(CameraCapabilitySeeder::class);
        $camera = CameraModel::query()->where('slug', 'fujifilm-x-s20')->firstOrFail();
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $this->postJson('/api/v1/recipes', [
            'name' => 'Valid X-S20 Recipe',
            'camera_model_id' => $camera->id,
            'settings' => [
                ['setting_key' => 'film_simulation', 'value' => 'CLASSIC CHROME'],
                ['setting_key' => 'highlight_tone', 'value' => -2],
                ['setting_key' => 'grain_effect', 'value' => [
                    'roughness' => 'WEAK',
                    'size' => 'SMALL',
                ]],
            ],
        ])->assertOk()
            ->assertJsonPath('data.name', 'Valid X-S20 Recipe');

        $this->postJson('/api/v1/recipes', [
            'name' => 'Out Of Range Recipe',
            'camera_model_id' => $camera->id,
            'settings' => [
                ['setting_key' => 'highlight_tone', 'value' => 5],
            ],
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');

        $this->postJson('/api/v1/recipes', [
            'name' => 'Unsupported Value Recipe',
            'camera_model_id' => $camera->id,
            'settings' => [
                ['setting_key' => 'film_simulation', 'value' => 'NOT A FUJIFILM SIMULATION'],
            ],
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');

        $this->postJson('/api/v1/recipes', [
            'name' => 'Unsupported Key Recipe',
            'camera_model_id' => $camera->id,
            'settings' => [
                ['setting_key' => 'not_supported_by_x_s20', 'value' => 'value'],
            ],
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');

        $this->assertDatabaseCount('recipes', 1);
        $this->assertDatabaseHas('recipes', [
            'name' => 'Valid X-S20 Recipe',
            'status' => Recipe::STATUS_PRIVATE,
        ]);
    }

    public function test_x_t5_has_model_specific_film_simulation_and_iso_values(): void
    {
        $this->seed(CameraCapabilitySeeder::class);
        $camera = CameraModel::query()->where('slug', 'fujifilm-x-t5')->firstOrFail();
        $user = User::factory()->create();
        Sanctum::actingAs($user);

        $this->postJson('/api/v1/recipes', [
            'name' => 'Valid X-T5 Recipe',
            'camera_model_id' => $camera->id,
            'settings' => [
                ['setting_key' => 'film_simulation', 'value' => 'REALA ACE'],
                ['setting_key' => 'iso', 'value' => 64],
            ],
        ])->assertOk();

        $this->postJson('/api/v1/recipes', [
            'name' => 'X-T5 AUTO Simulation',
            'camera_model_id' => $camera->id,
            'settings' => [
                ['setting_key' => 'film_simulation', 'value' => 'AUTO'],
            ],
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');
    }
}
