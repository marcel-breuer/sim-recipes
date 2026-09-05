<?php

namespace Tests\Feature;

use App\Models\CameraCapability;
use App\Models\CameraModel;
use App\Models\Category;
use App\Models\Recipe;
use App\Models\RecipeImage;
use App\Models\RecipeSetting;
use App\Models\Tag;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RecipeCopyTest extends TestCase
{
    use RefreshDatabase;

    public function test_authenticated_copy_is_transactional_and_preserves_provenance_relations_and_images(): void
    {
        Storage::fake('local');
        config(['filesystems.default' => 'local']);

        $author = User::factory()->create(['name' => 'Original author']);
        $copier = User::factory()->create(['name' => 'Copy owner']);
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
        $capability = CameraCapability::create([
            'camera_model_id' => $camera->id,
            'setting_key' => 'film_simulation',
            'display_name' => 'Film Simulation',
            'value_type' => 'enum',
            'allowed_values' => ['Classic Chrome'],
        ]);
        $category = Category::create(['name' => 'Street', 'slug' => 'street']);
        $tag = Tag::create(['name' => 'Muted', 'slug' => 'muted']);
        $source = Recipe::create([
            'user_id' => $author->id,
            'camera_model_id' => $camera->id,
            'name' => 'Source recipe',
            'description' => 'Original description',
            'recommendation' => 'Soft light',
            'lens' => '23mm',
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);
        $source->categories()->attach($category);
        $source->tags()->attach($tag);
        RecipeSetting::create([
            'recipe_id' => $source->id,
            'camera_capability_id' => $capability->id,
            'setting_key' => 'film_simulation',
            'value' => 'Classic Chrome',
        ]);
        $originalPath = 'recipes/'.$source->id.'/original.jpg';
        $thumbnailPath = 'recipes/'.$source->id.'/thumbnail.jpg';
        Storage::disk('local')->put($originalPath, 'original');
        Storage::disk('local')->put($thumbnailPath, 'thumbnail');
        RecipeImage::create([
            'recipe_id' => $source->id,
            'storage_disk' => 'local',
            'original_path' => $originalPath,
            'original_size_bytes' => 8,
            'mime_type' => 'image/jpeg',
            'width' => 100,
            'height' => 100,
            'derivatives' => ['thumbnail' => $thumbnailPath],
            'processing_status' => 'ready',
        ]);

        Sanctum::actingAs($copier);
        $response = $this->postJson('/api/v1/recipes/'.$source->id.'/copy')
            ->assertOk()
            ->assertJsonPath('data.status', Recipe::STATUS_PRIVATE)
            ->assertJsonPath('data.provenance.source_recipe_id', $source->id)
            ->assertJsonPath('data.provenance.source_author_id', $author->id);

        $copyID = $response->json('data.id');
        $copy = Recipe::query()->with(['categories', 'tags', 'settings', 'provenance', 'images'])->findOrFail($copyID);
        $this->assertSame($copier->id, $copy->user_id);
        $this->assertSame($category->id, $copy->categories->first()->id);
        $this->assertSame($tag->id, $copy->tags->first()->id);
        $this->assertSame('Classic Chrome', $copy->settings->first()->value);
        $this->assertSame($source->id, $copy->provenance->source_recipe_id);
        $this->assertSame($author->id, $copy->provenance->source_author_id);
        $this->assertDatabaseHas('recipe_downloads', [
            'recipe_id' => $source->id,
            'user_id' => $copier->id,
            'copied_recipe_id' => $copy->id,
        ]);
        $this->assertSame(1, $source->refresh()->downloads_count);
        $this->assertCount(1, $copy->images);
        Storage::disk('local')->assertExists($copy->images->first()->original_path);
        Storage::disk('local')->assertExists($copy->images->first()->derivatives['thumbnail']);
    }

    public function test_private_recipes_cannot_be_copied_and_copy_requires_authentication(): void
    {
        $owner = User::factory()->create();
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
        $private = Recipe::create([
            'user_id' => $owner->id,
            'camera_model_id' => $camera->id,
            'name' => 'Private recipe',
        ]);

        $this->postJson('/api/v1/recipes/'.$private->id.'/copy')->assertUnauthorized();
        Sanctum::actingAs($owner);
        $this->postJson('/api/v1/recipes/'.$private->id.'/copy')->assertNotFound();
    }
}
