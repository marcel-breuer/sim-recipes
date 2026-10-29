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
use Tests\TestCase;

class CommunityRecipeFeedTest extends TestCase
{
    use RefreshDatabase;

    public function test_anonymous_feed_contains_only_published_recipes_with_deterministic_pagination(): void
    {
        $user = User::factory()->create();
        $camera = $this->createCamera('x-s20');
        $publishedAt = now()->subDay();
        $recipes = collect(['First', 'Second', 'Third'])->map(function (string $name) use ($user, $camera, $publishedAt): Recipe {
            return Recipe::create([
                'user_id' => $user->id,
                'camera_model_id' => $camera->id,
                'name' => $name,
                'status' => Recipe::STATUS_PUBLISHED,
                'published_at' => $publishedAt,
            ]);
        });
        Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $camera->id,
            'name' => 'Private Draft',
        ]);

        $page = $this->getJson('/api/v1/recipes?feed=newest&per_page=2')
            ->assertOk()
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('meta.current_page', 1)
            ->assertJsonPath('meta.last_page', 2)
            ->assertJsonPath('meta.total', 3);

        $this->assertSame(
            $recipes->sortByDesc('id')->take(2)->pluck('id')->values()->all(),
            collect($page->json('data'))->pluck('id')->all(),
        );
        $this->assertNotContains('Private Draft', collect($page->json('data'))->pluck('name')->all());
    }

    public function test_search_and_all_discovery_filters_are_composable(): void
    {
        $user = User::factory()->create();
        $camera = $this->createCamera('x-s20');
        $otherCamera = $this->createCamera('x-t5');
        $category = Category::create(['name' => 'Street', 'slug' => 'street']);
        $tag = Tag::create(['name' => 'Muted', 'slug' => 'muted']);
        $capability = CameraCapability::create([
            'camera_model_id' => $camera->id,
            'setting_key' => 'film_simulation',
            'display_name' => 'Film Simulation',
            'value_type' => 'enum',
            'allowed_values' => ['Classic Chrome', 'Velvia'],
        ]);

        $matching = $this->createPublishedRecipe($user, $camera, 'Muted Street', 'A classic chrome recipe.');
        $matching->categories()->attach($category);
        $matching->tags()->attach($tag);
        RecipeSetting::create([
            'recipe_id' => $matching->id,
            'camera_capability_id' => $capability->id,
            'setting_key' => 'film_simulation',
            'value' => 'Classic Chrome',
        ]);

        $wrongTag = $this->createPublishedRecipe($user, $camera, 'Bright Street', 'A classic chrome recipe.');
        $wrongTag->categories()->attach($category);
        $wrongTag->tags()->attach(Tag::create(['name' => 'Bright', 'slug' => 'bright']));
        $wrongCamera = $this->createPublishedRecipe($user, $otherCamera, 'Muted Street', 'A classic chrome recipe.');
        $wrongCamera->categories()->attach($category);
        $wrongCamera->tags()->attach($tag);

        $this->getJson('/api/v1/recipes?search=muted&camera_model_id='.$camera->id.'&film_simulation=Classic%20Chrome&categories[]=street&tags[]=muted')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $matching->id)
            ->assertJsonPath('data.0.name', 'Muted Street');
    }

    public function test_compatibility_evidence_filter_requires_every_setting_to_meet_the_requested_level(): void
    {
        $user = User::factory()->create();
        $camera = $this->createCamera('x-s20');
        $verified = CameraCapability::create([
            'camera_model_id' => $camera->id,
            'setting_key' => 'film_simulation',
            'display_name' => 'Film Simulation',
            'value_type' => 'enum',
            'allowed_values' => ['Classic Chrome'],
            'evidence_level' => 'camera_verified',
            'evidence_source' => 'X-S20 hardware validation record',
            'verified_firmware' => '1.31',
            'verified_at' => now(),
        ]);
        $catalogOnly = CameraCapability::create([
            'camera_model_id' => $camera->id,
            'setting_key' => 'grain_effect',
            'display_name' => 'Grain Effect',
            'value_type' => 'enum',
            'allowed_values' => ['OFF', 'WEAK'],
            'evidence_level' => 'catalog_only',
        ]);

        $fullyVerified = $this->createPublishedRecipe($user, $camera, 'Verified recipe', 'Camera checked.');
        RecipeSetting::create([
            'recipe_id' => $fullyVerified->id,
            'camera_capability_id' => $verified->id,
            'setting_key' => 'film_simulation',
            'value' => 'Classic Chrome',
        ]);

        $mixedEvidence = $this->createPublishedRecipe($user, $camera, 'Mixed evidence recipe', 'One setting is catalogue-only.');
        RecipeSetting::create([
            'recipe_id' => $mixedEvidence->id,
            'camera_capability_id' => $verified->id,
            'setting_key' => 'film_simulation',
            'value' => 'Classic Chrome',
        ]);
        RecipeSetting::create([
            'recipe_id' => $mixedEvidence->id,
            'camera_capability_id' => $catalogOnly->id,
            'setting_key' => 'grain_effect',
            'value' => 'WEAK',
        ]);

        $this->getJson('/api/v1/recipes?camera_model_id='.$camera->id.'&compatibility_evidence=camera_verified')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $fullyVerified->id);

        $this->getJson('/api/v1/recipes?compatibility_evidence=camera_verified')
            ->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');
    }

    public function test_example_context_filters_match_one_example_image_and_allow_alternatives_within_a_facet(): void
    {
        $user = User::factory()->create();
        $camera = $this->createCamera('x-s20');

        $matching = $this->createPublishedRecipe($user, $camera, 'Muted street', 'A context-matched example.');
        $this->addExampleContext($matching, [
            'subjects' => ['street'],
            'lighting' => ['overcast'],
            'looks' => ['muted'],
        ]);

        $contextSplitAcrossImages = $this->createPublishedRecipe($user, $camera, 'Split context', 'Labels belong to separate photos.');
        $this->addExampleContext($contextSplitAcrossImages, [
            'subjects' => ['street'],
            'lighting' => ['golden_hour'],
            'looks' => ['muted'],
        ]);
        $this->addExampleContext($contextSplitAcrossImages, [
            'subjects' => ['portrait'],
            'lighting' => ['overcast'],
            'looks' => ['muted'],
        ], 1);

        $wrongLook = $this->createPublishedRecipe($user, $camera, 'Warm street', 'A different color character.');
        $this->addExampleContext($wrongLook, [
            'subjects' => ['street'],
            'lighting' => ['overcast'],
            'looks' => ['warm'],
        ]);

        $response = $this->getJson('/api/v1/recipes?subjects[]=street&lighting[]=overcast&looks[]=muted')
            ->assertOk()
            ->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $matching->id)
            ->assertJsonPath('data.0.images.0.example_context.looks.0', 'muted');

        $this->assertSame([$matching->id], collect($response->json('data'))->pluck('id')->all());

        $alternatives = $this->getJson('/api/v1/recipes?subjects[]=street&subjects[]=portrait')
            ->assertOk();
        $this->assertContains($matching->id, collect($alternatives->json('data'))->pluck('id')->all());

        $this->getJson('/api/v1/recipes?looks[]=invented')
            ->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');
    }

    public function test_similar_recipes_use_deterministic_camera_metadata_and_settings(): void
    {
        $user = User::factory()->create();
        $camera = $this->createCamera('x-s20');
        $otherCamera = $this->createCamera('x-t5');
        $category = Category::create(['name' => 'Street', 'slug' => 'street']);
        $tag = Tag::create(['name' => 'Muted', 'slug' => 'muted']);
        $capability = CameraCapability::create([
            'camera_model_id' => $camera->id,
            'setting_key' => 'film_simulation',
            'display_name' => 'Film Simulation',
            'value_type' => 'enum',
            'allowed_values' => ['Classic Chrome', 'Velvia'],
        ]);

        $source = $this->createPublishedRecipe($user, $camera, 'Source', 'Source recipe.');
        $source->categories()->attach($category);
        $source->tags()->attach($tag);
        RecipeSetting::create([
            'recipe_id' => $source->id,
            'camera_capability_id' => $capability->id,
            'setting_key' => 'film_simulation',
            'value' => 'Classic Chrome',
        ]);

        $matching = $this->createPublishedRecipe($user, $camera, 'Matching', 'Matching recipe.');
        $matching->categories()->attach($category);
        $matching->tags()->attach($tag);
        RecipeSetting::create([
            'recipe_id' => $matching->id,
            'camera_capability_id' => $capability->id,
            'setting_key' => 'film_simulation',
            'value' => 'Classic Chrome',
        ]);

        $sameCamera = $this->createPublishedRecipe($user, $camera, 'Same camera', 'Different metadata.');
        $wrongCamera = $this->createPublishedRecipe($user, $otherCamera, 'Wrong camera', 'Matching tags, wrong camera.');
        $source->refresh();

        $response = $this->getJson('/api/v1/recipes/'.$source->id.'/similar')
            ->assertOk()
            ->assertJsonPath('data.0.id', $matching->id);

        $ids = collect($response->json('data'))->pluck('id');
        $this->assertContains($sameCamera->id, $ids);
        $this->assertNotContains($source->id, $ids);
        $this->assertNotContains($wrongCamera->id, $ids);
    }

    private function createCamera(string $slug): CameraModel
    {
        return CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => strtoupper($slug),
            'slug' => $slug,
        ]);
    }

    private function createPublishedRecipe(User $user, CameraModel $camera, string $name, string $description): Recipe
    {
        return Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $camera->id,
            'name' => $name,
            'description' => $description,
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);
    }

    /** @param array<string, array<int, string>> $context */
    private function addExampleContext(Recipe $recipe, array $context, int $sortOrder = 0): RecipeImage
    {
        return RecipeImage::create([
            'recipe_id' => $recipe->id,
            'storage_disk' => 'local',
            'original_path' => 'examples/'.$recipe->id.'/'.$sortOrder.'.jpg',
            'original_size_bytes' => 1,
            'mime_type' => 'image/jpeg',
            'sort_order' => $sortOrder,
            'example_context' => $context,
        ]);
    }
}
