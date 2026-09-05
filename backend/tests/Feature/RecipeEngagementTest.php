<?php

namespace Tests\Feature;

use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\User;
use App\Services\Recipes\RecipeEngagementService;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RecipeEngagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_authenticated_like_and_unlike_are_idempotent_and_private_recipes_are_hidden(): void
    {
        $user = User::factory()->create();
        $recipe = $this->createPublishedRecipe($user, 'Public recipe');
        $private = Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $recipe->camera_model_id,
            'name' => 'Private recipe',
        ]);
        Sanctum::actingAs($user);

        $this->postJson('/api/v1/recipes/'.$recipe->id.'/like')
            ->assertOk()
            ->assertJsonPath('data.liked', true)
            ->assertJsonPath('data.likes_count', 1);
        $this->postJson('/api/v1/recipes/'.$recipe->id.'/like')
            ->assertOk()
            ->assertJsonPath('data.likes_count', 1);
        $this->deleteJson('/api/v1/recipes/'.$recipe->id.'/like')
            ->assertOk()
            ->assertJsonPath('data.liked', false)
            ->assertJsonPath('data.likes_count', 0);
        $this->deleteJson('/api/v1/recipes/'.$recipe->id.'/like')
            ->assertOk()
            ->assertJsonPath('data.likes_count', 0);

        $this->postJson('/api/v1/recipes/'.$private->id.'/like')->assertNotFound();
        $this->assertDatabaseCount('likes', 0);
    }

    public function test_anonymous_views_are_deduplicated_per_recipe_and_actor_window(): void
    {
        $user = User::factory()->create();
        $recipe = $this->createPublishedRecipe($user, 'Public recipe');

        $this->withHeader('X-Anonymous-Key', 'visitor-a')
            ->postJson('/api/v1/recipes/'.$recipe->id.'/view')
            ->assertOk()
            ->assertJsonPath('data.recorded', true)
            ->assertJsonPath('data.views_count', 1);
        $this->withHeader('X-Anonymous-Key', 'visitor-a')
            ->postJson('/api/v1/recipes/'.$recipe->id.'/view')
            ->assertOk()
            ->assertJsonPath('data.recorded', false)
            ->assertJsonPath('data.views_count', 1);
        $this->withHeader('X-Anonymous-Key', 'visitor-b')
            ->postJson('/api/v1/recipes/'.$recipe->id.'/view')
            ->assertOk()
            ->assertJsonPath('data.recorded', true)
            ->assertJsonPath('data.views_count', 2);
        $this->assertDatabaseCount('recipe_views', 2);
    }

    public function test_popular_feed_uses_replaceable_weighted_ranking(): void
    {
        $user = User::factory()->create();
        $first = $this->createPublishedRecipe($user, 'Likes');
        $first->update(['likes_count' => 1]);
        $second = $this->createPublishedRecipe($user, 'Views');
        $second->update(['views_count' => 4]);
        $third = $this->createPublishedRecipe($user, 'Downloads');
        $third->update(['downloads_count' => 1]);

        $this->getJson('/api/v1/recipes?feed=popular')
            ->assertOk()
            ->assertJsonPath('data.0.name', 'Downloads')
            ->assertJsonPath('data.1.name', 'Views')
            ->assertJsonPath('data.2.name', 'Likes');
    }

    public function test_download_events_increment_only_the_source_recipe_counter(): void
    {
        $user = User::factory()->create();
        $source = $this->createPublishedRecipe($user, 'Source');
        $copy = Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $source->camera_model_id,
            'name' => 'Copy',
        ]);

        $download = app(RecipeEngagementService::class)->recordDownload($source, $user, $copy);

        $this->assertSame($copy->id, $download->copied_recipe_id);
        $this->assertDatabaseHas('recipe_downloads', [
            'recipe_id' => $source->id,
            'user_id' => $user->id,
            'copied_recipe_id' => $copy->id,
        ]);
        $this->assertSame(1, $source->refresh()->downloads_count);
        $this->assertSame(0, $copy->refresh()->downloads_count);
    }

    private function createPublishedRecipe(User $user, string $name): Recipe
    {
        $camera = CameraModel::firstOrCreate(
            ['slug' => 'x-s20'],
            ['manufacturer' => 'Fujifilm', 'name' => 'X-S20'],
        );

        return Recipe::create([
            'user_id' => $user->id,
            'camera_model_id' => $camera->id,
            'name' => $name,
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);
    }
}
