<?php

namespace Tests\Feature;

use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\RecipeComment;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RecipeCommentsTest extends TestCase
{
    use RefreshDatabase;

    public function test_users_can_list_and_create_comments_on_public_recipes(): void
    {
        $author = User::factory()->create(['name' => 'Recipe Author']);
        $commenter = User::factory()->create(['name' => 'Comment Author']);
        $recipe = $this->createPublishedRecipe($author);

        Sanctum::actingAs($commenter);
        $created = $this->postJson('/api/v1/recipes/'.$recipe->id.'/comments', [
            'body' => 'This is a useful X-S20 starting point.',
        ])->assertCreated()
            ->assertJsonPath('data.body', 'This is a useful X-S20 starting point.')
            ->assertJsonPath('data.author.name', 'Comment Author')
            ->assertJsonPath('data.can_delete', true);

        Sanctum::actingAs($author);
        $this->getJson('/api/v1/recipes/'.$recipe->id.'/comments')
            ->assertOk()
            ->assertJsonPath('data.0.id', $created->json('data.id'))
            ->assertJsonPath('data.0.can_delete', false);
    }

    public function test_objectionable_comment_text_is_rejected_before_storage(): void
    {
        $user = User::factory()->create();
        $recipe = $this->createPublishedRecipe(User::factory()->create());
        Sanctum::actingAs($user);

        $this->postJson('/api/v1/recipes/'.$recipe->id.'/comments', [
            'body' => 'Porn comment',
        ])->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');

        $this->assertDatabaseMissing('recipe_comments', ['body' => 'Porn comment']);
    }

    public function test_only_the_comment_author_can_delete_a_comment(): void
    {
        $author = User::factory()->create();
        $otherUser = User::factory()->create();
        $comment = RecipeComment::create([
            'recipe_id' => $this->createPublishedRecipe(User::factory()->create())->id,
            'user_id' => $author->id,
            'body' => 'Keep this comment focused.',
        ]);

        Sanctum::actingAs($otherUser);
        $this->deleteJson('/api/v1/comments/'.$comment->id)->assertForbidden();

        Sanctum::actingAs($author);
        $this->deleteJson('/api/v1/comments/'.$comment->id)
            ->assertOk()
            ->assertJsonPath('data.deleted', true);

        $this->assertSoftDeleted('recipe_comments', ['id' => $comment->id]);
    }

    public function test_admin_can_hide_a_reported_comment(): void
    {
        $author = User::factory()->create();
        $reporter = User::factory()->create();
        $admin = User::factory()->create();
        $admin->forceFill(['is_admin' => true])->save();
        $recipe = $this->createPublishedRecipe($author);
        $comment = RecipeComment::create([
            'recipe_id' => $recipe->id,
            'user_id' => $author->id,
            'body' => 'Reported comment',
        ]);

        Sanctum::actingAs($reporter);
        $report = $this->postJson('/api/v1/comments/'.$comment->id.'/reports', [
            'reason' => 'harassment',
        ])->assertCreated();

        Sanctum::actingAs($admin);
        $this->patchJson('/api/v1/admin/reports/'.$report->json('data.id'), [
            'status' => 'resolved',
            'resolution' => 'hide_content',
        ])->assertOk();

        $this->assertDatabaseHas('recipe_comments', [
            'id' => $comment->id,
            'is_hidden' => true,
        ]);
        $this->getJson('/api/v1/recipes/'.$recipe->id.'/comments')
            ->assertOk()
            ->assertJsonCount(0, 'data');
    }

    private function createPublishedRecipe(User $author): Recipe
    {
        return Recipe::create([
            'user_id' => $author->id,
            'camera_model_id' => $this->createCamera()->id,
            'name' => 'X-S20 Community Recipe',
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);
    }

    private function createCamera(): CameraModel
    {
        return CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20-'.str()->random(6),
        ]);
    }
}
