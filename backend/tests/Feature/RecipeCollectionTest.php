<?php

namespace Tests\Feature;

use App\Models\CameraModel;
use App\Models\Profile;
use App\Models\Recipe;
use App\Models\RecipeCollection;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class RecipeCollectionTest extends TestCase
{
    use RefreshDatabase;

    public function test_owner_can_create_update_reorder_and_delete_collections_and_manage_membership(): void
    {
        $owner = User::factory()->create();
        $otherUser = User::factory()->create();
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
        $recipe = Recipe::create([
            'user_id' => $owner->id,
            'camera_model_id' => $camera->id,
            'name' => 'Published Chrome',
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);
        Sanctum::actingAs($owner);

        $response = $this->postJson('/api/v1/collections', [
            'name' => 'Street set',
            'is_public' => false,
        ])->assertCreated()
            ->assertJsonPath('data.name', 'Street set')
            ->assertJsonPath('data.sort_order', 1);
        $collectionID = $response->json('data.id');

        $this->putJson("/api/v1/collections/{$collectionID}/recipes/{$recipe->id}")
            ->assertOk()
            ->assertJsonPath('data.recipes.0.id', $recipe->id);

        $this->patchJson("/api/v1/collections/{$collectionID}", [
            'name' => 'Renamed set',
            'is_public' => true,
            'sort_order' => 0,
        ])->assertOk()
            ->assertJsonPath('data.name', 'Renamed set')
            ->assertJsonPath('data.is_public', true);

        $second = RecipeCollection::create([
            'user_id' => $owner->id,
            'name' => 'Second set',
            'sort_order' => 1,
        ]);
        $this->patchJson('/api/v1/collections/reorder', [
            'collection_ids' => [$second->id, $collectionID],
        ])->assertOk()
            ->assertJsonPath('data.0.id', $second->id)
            ->assertJsonPath('data.1.id', $collectionID);

        Sanctum::actingAs($otherUser);
        $this->patchJson("/api/v1/collections/{$collectionID}", ['name' => 'No access'])
            ->assertForbidden();
        $this->deleteJson("/api/v1/collections/{$collectionID}")
            ->assertForbidden();

        Sanctum::actingAs($owner);
        $this->deleteJson("/api/v1/collections/{$collectionID}")
            ->assertOk()
            ->assertJsonPath('data.deleted', true);
        $this->assertDatabaseMissing('recipe_collections', ['id' => $collectionID]);
    }

    public function test_public_profile_only_exposes_public_collections_and_published_members(): void
    {
        $creator = User::factory()->create(['name' => 'Creator']);
        $camera = CameraModel::create([
            'manufacturer' => 'Fujifilm',
            'name' => 'X-S20',
            'slug' => 'x-s20',
        ]);
        Profile::create([
            'user_id' => $creator->id,
            'username' => 'creator',
        ]);
        $published = Recipe::create([
            'user_id' => $creator->id,
            'camera_model_id' => $camera->id,
            'name' => 'Published Chrome',
            'status' => Recipe::STATUS_PUBLISHED,
            'published_at' => now(),
        ]);
        $private = Recipe::create([
            'user_id' => $creator->id,
            'camera_model_id' => $camera->id,
            'name' => 'Private Draft',
        ]);
        $publicCollection = RecipeCollection::create([
            'user_id' => $creator->id,
            'name' => 'Street set',
            'is_public' => true,
        ]);
        $privateCollection = RecipeCollection::create([
            'user_id' => $creator->id,
            'name' => 'Private set',
            'is_public' => false,
        ]);
        $publicCollection->recipes()->attach([
            $published->id => ['sort_order' => 0],
            $private->id => ['sort_order' => 1],
        ]);
        $privateCollection->recipes()->attach($published->id);

        $this->getJson('/api/v1/profiles/creator')
            ->assertOk()
            ->assertJsonPath('data.collections.0.name', 'Street set')
            ->assertJsonPath('data.collections.0.recipes.0.name', 'Published Chrome')
            ->assertJsonMissing(['name' => 'Private set'])
            ->assertJsonMissing(['name' => 'Private Draft']);
    }

    public function test_collection_index_is_private_to_authenticated_owner(): void
    {
        $owner = User::factory()->create();
        $otherUser = User::factory()->create();
        RecipeCollection::create([
            'user_id' => $owner->id,
            'name' => 'Owner set',
        ]);
        RecipeCollection::create([
            'user_id' => $otherUser->id,
            'name' => 'Other set',
        ]);

        Sanctum::actingAs($owner);
        $this->getJson('/api/v1/collections')
            ->assertOk()
            ->assertJsonPath('data.0.name', 'Owner set')
            ->assertJsonMissing(['name' => 'Other set']);
    }
}
