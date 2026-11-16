<?php

namespace Tests\Feature;

use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class MyRecipesApiTest extends TestCase
{
    use RefreshDatabase;

    public function test_library_requires_authentication_and_read_scope(): void
    {
        $this->getJson('/api/v1/me/recipes')->assertUnauthorized()->assertJsonPath('error.code', 'unauthenticated');

        Sanctum::actingAs(User::factory()->create(), ['write']);
        $this->getJson('/api/v1/me/recipes')->assertForbidden()->assertJsonPath('error.code', 'insufficient_scope');
    }

    public function test_library_lists_only_own_recipes_with_cursor_pagination_and_filters(): void
    {
        $camera = CameraModel::create(['manufacturer' => 'Fujifilm', 'name' => 'X-S20', 'slug' => 'x-s20']);
        $otherCamera = CameraModel::create(['manufacturer' => 'Fujifilm', 'name' => 'X-T5', 'slug' => 'x-t5']);
        $owner = User::factory()->create();
        $other = User::factory()->create();

        foreach (range(1, 5) as $index) {
            Recipe::create([
                'user_id' => $owner->id,
                'camera_model_id' => $index === 5 ? $otherCamera->id : $camera->id,
                'name' => 'Recipe '.$index,
                'description' => $index === 2 ? 'warm portrait look' : null,
                'status' => $index % 2 === 0 ? Recipe::STATUS_PUBLISHED : Recipe::STATUS_PRIVATE,
                'published_at' => $index % 2 === 0 ? now() : null,
                'created_at' => now()->subMinutes(10 - $index),
            ]);
        }
        Recipe::create(['user_id' => $owner->id, 'camera_model_id' => $camera->id, 'name' => 'Hidden', 'is_hidden' => true]);
        Recipe::create(['user_id' => $other->id, 'camera_model_id' => $camera->id, 'name' => 'Not mine']);

        Sanctum::actingAs($owner, ['read']);

        $first = $this->getJson('/api/v1/me/recipes?per_page=2')->assertOk();
        $first->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.name', 'Recipe 5')
            ->assertJsonPath('data.1.name', 'Recipe 4');
        $cursor = $first->json('meta.next_cursor');
        self::assertNotNull($cursor);

        $second = $this->getJson('/api/v1/me/recipes?per_page=2&cursor='.urlencode($cursor))->assertOk();
        $second->assertJsonPath('data.0.name', 'Recipe 3')->assertJsonPath('data.1.name', 'Recipe 2');

        $last = $this->getJson('/api/v1/me/recipes?per_page=2&cursor='.urlencode($second->json('meta.next_cursor')))->assertOk();
        $last->assertJsonCount(1, 'data')->assertJsonPath('meta.next_cursor', null);

        $this->getJson('/api/v1/me/recipes?status=published')->assertJsonCount(2, 'data');
        $this->getJson('/api/v1/me/recipes?status=private')->assertJsonCount(3, 'data');
        $this->getJson('/api/v1/me/recipes?camera_model_id='.$otherCamera->id)->assertJsonCount(1, 'data');
        $this->getJson('/api/v1/me/recipes?search=PORTRAIT')->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.name', 'Recipe 2');
    }

    public function test_library_validates_filters(): void
    {
        Sanctum::actingAs(User::factory()->create(), ['read']);

        $this->getJson('/api/v1/me/recipes?status=archived')->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');
        $this->getJson('/api/v1/me/recipes?per_page=1000')->assertUnprocessable();
        $this->getJson('/api/v1/me/recipes?camera_model_id=missing')->assertUnprocessable();
    }
}
