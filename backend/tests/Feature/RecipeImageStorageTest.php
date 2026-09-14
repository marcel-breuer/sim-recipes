<?php

namespace Tests\Feature;

use App\Jobs\GenerateRecipeImageDerivatives;
use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\RecipeImage;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\Storage;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RecipeImageStorageTest extends TestCase
{
    use RefreshDatabase;

    public function test_image_count_and_user_quota_are_enforced(): void
    {
        Storage::fake('local');
        Queue::fake();
        config(['filesystems.default' => 'local']);

        $user = User::factory()->create();
        $camera = $this->createCamera();
        Sanctum::actingAs($user);

        $response = $this->post('/api/v1/recipes', [
            'name' => 'Five Images',
            'camera_model_id' => $camera->id,
            'images' => array_map(
                static fn (int $number): UploadedFile => UploadedFile::fake()->image($number.'.jpg'),
                range(1, 5),
            ),
        ])->assertOk();

        $recipeID = $response->json('data.id');
        $this->assertDatabaseCount('recipe_images', 5);
        Queue::assertPushed(GenerateRecipeImageDerivatives::class, 5);

        $this->patch('/api/v1/recipes/'.$recipeID, [
            'images' => [UploadedFile::fake()->image('sixth.jpg')],
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');

        $this->post('/api/v1/recipes', [
            'name' => 'Large Image',
            'camera_model_id' => $camera->id,
            'images' => [UploadedFile::fake()->create('large.jpg', 25601, 'image/jpeg')],
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');

        config(['recipes.images.user_quota_bytes' => 1]);
        $this->post('/api/v1/recipes', [
            'name' => 'Over Quota',
            'camera_model_id' => $camera->id,
            'images' => [UploadedFile::fake()->image('over-quota.jpg')],
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');
    }

    public function test_private_images_are_authorized_and_published_images_are_publicly_readable(): void
    {
        Storage::fake('local');
        Queue::fake();
        config(['filesystems.default' => 'local']);

        $owner = User::factory()->create();
        $otherUser = User::factory()->create();
        $camera = $this->createCamera();
        Sanctum::actingAs($owner);

        $response = $this->post('/api/v1/recipes', [
            'name' => 'Private Image',
            'camera_model_id' => $camera->id,
            'images' => [UploadedFile::fake()->image('private.jpg')],
        ])->assertOk();
        $imageURL = $response->json('data.images.0.url');
        $imageID = $response->json('data.images.0.id');

        (new GenerateRecipeImageDerivatives($imageID))->handle();

        $this->get($imageURL)->assertOk();
        $this->get($imageURL.'?variant=thumbnail')->assertOk();
        $this->get($imageURL.'?variant=detail')->assertOk();

        Sanctum::actingAs($otherUser);
        $this->get($imageURL)->assertForbidden();
        $this->get($imageURL.'?variant=thumbnail')->assertForbidden();
        $this->get($imageURL.'?variant=detail')->assertForbidden();

        Sanctum::actingAs($owner);
        $this->postJson('/api/v1/recipes/'.$response->json('data.id').'/publish')->assertOk();

        Sanctum::actingAs($otherUser);
        $this->get($imageURL)->assertOk();
    }

    public function test_published_images_never_serve_the_original_variant(): void
    {
        Storage::fake('local');
        Queue::fake();
        config(['filesystems.default' => 'local']);

        $owner = User::factory()->create();
        $otherUser = User::factory()->create();
        $camera = $this->createCamera();
        Sanctum::actingAs($owner);

        $response = $this->post('/api/v1/recipes', [
            'name' => 'Variant Access',
            'camera_model_id' => $camera->id,
            'images' => [UploadedFile::fake()->image('variant.jpg', 2000, 1000)],
        ])->assertOk();
        $imageID = $response->json('data.images.0.id');
        $imageURL = $response->json('data.images.0.url');

        (new GenerateRecipeImageDerivatives($imageID))->handle();
        $this->postJson('/api/v1/recipes/'.$response->json('data.id').'/publish')->assertOk();

        Sanctum::actingAs($otherUser);
        $this->get($imageURL)->assertOk();
        $this->get($imageURL.'?variant=thumbnail')->assertOk();
        $this->get($imageURL.'?variant=detail')->assertOk();
        $this->get($imageURL.'?variant=original')->assertNotFound();
    }

    public function test_derivative_job_keeps_the_original_and_records_derivative_paths(): void
    {
        Storage::fake('local');
        config(['filesystems.default' => 'local']);

        $user = User::factory()->create();
        $camera = $this->createCamera();
        $recipe = Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $camera->id,
            'name' => 'Derivative Recipe',
        ]);
        $originalPath = UploadedFile::fake()->image('original.jpg', 2000, 1000)->store(
            'recipes/'.$recipe->id,
            'local',
        );
        $image = RecipeImage::create([
            'recipe_id' => $recipe->id,
            'storage_disk' => 'local',
            'original_path' => $originalPath,
            'original_size_bytes' => Storage::disk('local')->size($originalPath),
            'mime_type' => 'image/jpeg',
        ]);

        (new GenerateRecipeImageDerivatives($image->id))->handle();

        $image->refresh();
        $derivatives = $image->getAttribute('derivatives');
        $this->assertSame('ready', $image->processing_status);
        $this->assertIsArray($derivatives);
        $this->assertArrayHasKey('thumbnail', $derivatives);
        $this->assertArrayHasKey('detail', $derivatives);
        $this->assertTrue(Storage::disk('local')->exists($originalPath));
        $this->assertTrue(Storage::disk('local')->exists($derivatives['thumbnail']));
        $this->assertTrue(Storage::disk('local')->exists($derivatives['detail']));
        $this->assertSame(2000, $image->width);
        $this->assertSame(1000, $image->height);
        $this->assertStringNotContainsString('Exif', Storage::disk('local')->get($derivatives['thumbnail']));
        $this->assertStringNotContainsString('GPS', Storage::disk('local')->get($derivatives['thumbnail']));
    }

    public function test_metadata_policy_is_explicit_for_originals_and_derivatives(): void
    {
        $metadata = config('recipes.images.metadata');

        $this->assertSame(
            'retained privately while a recipe is private; never served after publication',
            $metadata['originals'],
        );
        $this->assertSame(
            'EXIF and GPS metadata stripped during WebP encoding',
            $metadata['derivatives'],
        );
    }

    public function test_deleting_a_recipe_removes_originals_and_derivatives(): void
    {
        Storage::fake('local');
        Queue::fake();
        config(['filesystems.default' => 'local']);

        $user = User::factory()->create();
        $camera = $this->createCamera();
        Sanctum::actingAs($user);
        $response = $this->post('/api/v1/recipes', [
            'name' => 'Deletable Image',
            'camera_model_id' => $camera->id,
            'images' => [UploadedFile::fake()->image('delete-me.jpg')],
        ])->assertOk();
        $image = RecipeImage::query()->firstOrFail();
        $originalPath = $image->original_path;

        $this->deleteJson('/api/v1/recipes/'.$response->json('data.id'))->assertOk();

        Storage::disk('local')->assertMissing($originalPath);
        $this->assertDatabaseMissing('recipe_images', ['id' => $image->id]);
    }

    public function test_private_owner_can_delete_an_image_but_published_images_are_immutable(): void
    {
        Storage::fake('local');
        Queue::fake();
        config(['filesystems.default' => 'local']);

        $user = User::factory()->create();
        $camera = $this->createCamera();
        Sanctum::actingAs($user);
        $privateResponse = $this->post('/api/v1/recipes', [
            'name' => 'Private Image Delete',
            'camera_model_id' => $camera->id,
            'images' => [UploadedFile::fake()->image('private-delete.jpg')],
        ])->assertOk();
        $privateImageID = $privateResponse->json('data.images.0.id');
        $privateImage = RecipeImage::query()->findOrFail($privateImageID);
        $privatePath = $privateImage->original_path;

        $this->deleteJson('/api/v1/recipe-images/'.$privateImageID)
            ->assertOk()
            ->assertJsonPath('data.deleted', true);
        Storage::disk('local')->assertMissing($privatePath);

        $publishedResponse = $this->post('/api/v1/recipes', [
            'name' => 'Published Image Delete',
            'camera_model_id' => $camera->id,
            'images' => [UploadedFile::fake()->image('published-delete.jpg')],
        ])->assertOk();
        $publishedImageID = $publishedResponse->json('data.images.0.id');
        $this->postJson('/api/v1/recipes/'.$publishedResponse->json('data.id').'/publish')->assertOk();

        $this->deleteJson('/api/v1/recipe-images/'.$publishedImageID)->assertForbidden();
        $this->assertDatabaseHas('recipe_images', ['id' => $publishedImageID]);
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
