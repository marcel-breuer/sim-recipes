<?php

namespace Tests\Feature;

use App\Models\CameraCapability;
use App\Models\CameraModel;
use App\Models\Category;
use App\Models\Like;
use App\Models\Profile;
use App\Models\Recipe;
use App\Models\RecipeDownload;
use App\Models\RecipeImage;
use App\Models\RecipeProvenance;
use App\Models\RecipeSetting;
use App\Models\RecipeView;
use App\Models\Tag;
use App\Models\User;
use Database\Seeders\CameraCapabilitySeeder;
use Illuminate\Database\QueryException;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Str;
use Tests\TestCase;

class DatabaseSchemaTest extends TestCase
{
    use RefreshDatabase;

    public function test_x_s20_capabilities_are_seeded_with_recipe_settings_and_slot_metadata(): void
    {
        $this->seed(CameraCapabilitySeeder::class);

        $camera = CameraModel::where('slug', 'fujifilm-x-s20')->firstOrFail();
        $capabilities = $camera->capabilities->keyBy('setting_key');

        $this->assertTrue($camera->is_supported);
        $this->assertSame('Fujifilm', $camera->manufacturer);
        $this->assertSame('X-S20', $camera->model_identifier);
        $this->assertEqualsCanonicalizing([
            'film_simulation',
            'dynamic_range',
            'grain_effect',
            'color_chrome_effect',
            'color_chrome_fx_blue',
            'white_balance',
            'white_balance_shift',
            'highlight_tone',
            'shadow_tone',
            'color',
            'sharpness',
            'high_iso_noise_reduction',
            'clarity',
            'iso',
            'exposure_compensation',
        ], $capabilities->keys()->all());

        $this->assertSame(['AUTO', '100%', '200%', '400%'], $capabilities['dynamic_range']->allowed_values);
        $this->assertSame(-5.0, (float) $capabilities['exposure_compensation']->minimum);
        $this->assertSame(5.0, (float) $capabilities['exposure_compensation']->maximum);
        $this->assertSame(0.333, (float) $capabilities['exposure_compensation']->step);
        $this->assertSame('object', $capabilities['white_balance_shift']->value_type);
        $this->assertSame(['C1', 'C2', 'C3', 'C4'], $capabilities['iso']->custom_slot_metadata['slot_names']);
        $this->assertSame(4, $capabilities['iso']->custom_slot_metadata['slot_count']);
        $this->assertEqualsCanonicalizing(
            ['monochromatic_color', 'smooth_skin_effect'],
            $camera->unsupported_recipe_settings,
        );
    }

    public function test_x_s20_capability_seeder_is_idempotent(): void
    {
        $this->seed(CameraCapabilitySeeder::class);
        $this->seed(CameraCapabilitySeeder::class);

        $this->assertDatabaseCount('camera_models', 2);
        $this->assertDatabaseCount('camera_capabilities', 30);
    }

    public function test_x_t5_capabilities_preserve_model_specific_ranges_and_slots(): void
    {
        $this->seed(CameraCapabilitySeeder::class);

        $camera = CameraModel::where('slug', 'fujifilm-x-t5')->firstOrFail();
        $capabilities = $camera->capabilities->keyBy('setting_key');

        $this->assertTrue($camera->is_supported);
        $this->assertSame('X-T5', $camera->model_identifier);
        $this->assertNotContains('AUTO', $capabilities['film_simulation']->allowed_values);
        $this->assertSame(64.0, (float) $capabilities['iso']->minimum);
        $this->assertSame(125, $capabilities['iso']->custom_slot_metadata['manual_range']['minimum']);
        $this->assertSame(['C1', 'C2', 'C3', 'C4', 'C5', 'C6', 'C7'], $capabilities['iso']->custom_slot_metadata['slot_names']);
        $this->assertSame(7, $capabilities['iso']->custom_slot_metadata['slot_count']);
        $this->assertSame('unverified', $camera->transport_metadata['property_reads']);
        $this->assertSame('unverified', $camera->transport_metadata['recipe_writes']);
    }

    public function test_core_recipe_graph_uses_ulids_and_preserves_provenance(): void
    {
        $author = User::factory()->create();
        $copier = User::factory()->create();
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'fujifilm-x-s20',
            'model_identifier' => 'X-S20',
            'is_supported' => true,
        ]);
        $capability = CameraCapability::create([
            'camera_model_id' => $camera->id,
            'setting_key' => 'film_simulation',
            'display_name' => 'Film Simulation',
            'value_type' => 'enum',
            'allowed_values' => ['Classic Chrome', 'PROVIA/Standard'],
            'transport_identifier' => 'film_simulation',
        ]);
        $profile = Profile::create([
            'user_id' => $author->id,
            'username' => 'recipe-author',
            'camera_model_id' => $camera->id,
        ]);
        $category = Category::create(['name' => 'Street', 'slug' => 'street']);
        $tag = Tag::create(['name' => 'Documentary', 'slug' => 'documentary']);
        $source = Recipe::create([
            'user_id' => $author->id,
            'camera_model_id' => $camera->id,
            'name' => 'Street Chrome',
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);
        $copy = Recipe::create([
            'user_id' => $copier->id,
            'camera_model_id' => $camera->id,
            'name' => 'Street Chrome Copy',
        ]);

        RecipeSetting::create([
            'recipe_id' => $source->id,
            'camera_capability_id' => $capability->id,
            'setting_key' => 'film_simulation',
            'value' => ['value' => 'Classic Chrome'],
        ]);
        RecipeImage::create([
            'recipe_id' => $source->id,
            'original_path' => 'recipes/'.$source->id.'/original.jpg',
            'original_size_bytes' => 1024,
            'mime_type' => 'image/jpeg',
        ]);
        $source->categories()->attach($category);
        $source->tags()->attach($tag);
        RecipeProvenance::create([
            'copied_recipe_id' => $copy->id,
            'source_recipe_id' => $source->id,
            'source_author_id' => $author->id,
            'copied_by_user_id' => $copier->id,
        ]);
        Like::create(['user_id' => $copier->id, 'recipe_id' => $source->id]);
        RecipeView::create(['recipe_id' => $source->id, 'anonymous_key' => 'anonymous-test']);
        RecipeDownload::create([
            'recipe_id' => $source->id,
            'user_id' => $copier->id,
            'copied_recipe_id' => $copy->id,
        ]);

        $this->assertTrue(Str::isUlid($author->id));
        $this->assertSame($author->id, $profile->user->id);
        $this->assertSame($camera->id, $source->cameraModel->id);
        $this->assertSame($category->id, $source->categories->first()->id);
        $this->assertSame($tag->id, $source->tags->first()->id);
        $this->assertSame($source->id, $copy->provenance->sourceRecipe->id);
        $this->assertSame($author->id, $copy->provenance->sourceAuthor->id);
        $this->assertDatabaseHas('recipe_settings', ['recipe_id' => $source->id]);
        $this->assertDatabaseHas('recipe_images', ['recipe_id' => $source->id]);
        $this->assertDatabaseCount('likes', 1);
        $this->assertDatabaseCount('recipe_views', 1);
        $this->assertDatabaseCount('recipe_downloads', 1);
    }

    public function test_like_uniqueness_is_enforced_by_the_database(): void
    {
        $user = User::factory()->create();
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
        $recipe = Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $camera->id,
            'name' => 'Test recipe',
        ]);

        Like::create(['user_id' => $user->id, 'recipe_id' => $recipe->id]);
        $this->expectException(QueryException::class);
        Like::create(['user_id' => $user->id, 'recipe_id' => $recipe->id]);
    }

    public function test_recipe_setting_keys_are_unique_per_recipe(): void
    {
        $user = User::factory()->create();
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
        $capability = CameraCapability::create([
            'camera_model_id' => $camera->id,
            'setting_key' => 'iso',
            'display_name' => 'ISO',
            'value_type' => 'integer',
        ]);
        $recipe = Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $camera->id,
            'name' => 'Test recipe',
        ]);
        RecipeSetting::create([
            'recipe_id' => $recipe->id,
            'camera_capability_id' => $capability->id,
            'setting_key' => 'iso',
            'value' => ['value' => 800],
        ]);

        $this->expectException(QueryException::class);
        RecipeSetting::create([
            'recipe_id' => $recipe->id,
            'camera_capability_id' => $capability->id,
            'setting_key' => 'iso',
            'value' => ['value' => 1600],
        ]);
    }

    public function test_published_recipes_require_a_publication_timestamp(): void
    {
        $user = User::factory()->create();
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
        $this->expectException(QueryException::class);
        Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $camera->id,
            'name' => 'Invalid published recipe',
            'status' => Recipe::STATUS_PUBLISHED,
        ]);
    }

    public function test_recipe_image_size_limit_is_enforced_by_the_database(): void
    {
        $user = User::factory()->create();
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
        $recipe = Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $camera->id,
            'name' => 'Test recipe',
        ]);

        $this->expectException(QueryException::class);
        RecipeImage::create([
            'recipe_id' => $recipe->id,
            'original_path' => 'too-large.jpg',
            'original_size_bytes' => 26214401,
            'mime_type' => 'image/jpeg',
        ]);
    }

    public function test_provenance_cannot_point_a_recipe_to_itself(): void
    {
        $user = User::factory()->create();
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
        $recipe = Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $camera->id,
            'name' => 'Test recipe',
        ]);

        $this->expectException(QueryException::class);
        RecipeProvenance::create([
            'copied_recipe_id' => $recipe->id,
            'source_recipe_id' => $recipe->id,
            'copied_by_user_id' => $user->id,
        ]);
    }
}
