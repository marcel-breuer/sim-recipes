<?php

namespace Tests\Feature;

use App\Models\CameraCapability;
use App\Models\CameraModel;
use App\Models\Category;
use App\Models\Recipe;
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
}
