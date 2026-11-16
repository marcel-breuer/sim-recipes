<?php

namespace Tests\Feature;

use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\RecipeCollection;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class PersonalAccessTokenTest extends TestCase
{
    use RefreshDatabase;

    public function test_first_party_session_can_create_list_and_revoke_scoped_tokens(): void
    {
        $user = User::factory()->create();
        $session = $user->createToken('ios', ['*'])->plainTextToken;

        $created = $this->withToken($session)->postJson('/api/v1/me/tokens', [
            'name' => 'Claude Desktop',
            'abilities' => ['read', 'write'],
            'expires_in_days' => 7,
        ])->assertCreated()
            ->assertJsonPath('data.name', 'Claude Desktop')
            ->assertJsonPath('data.abilities', ['read', 'write']);
        $secret = $created->json('data.token');
        self::assertNotEmpty($secret);

        $this->forgetGuards();
        $list = $this->withToken($session)->getJson('/api/v1/me/tokens')->assertOk();
        $list->assertJsonCount(1, 'data')
            ->assertJsonPath('data.0.id', $created->json('data.id'))
            ->assertJsonMissingPath('data.0.token');
        self::assertStringNotContainsString($secret, $list->getContent());
        self::assertNotNull($list->json('meta.per_page'));

        $this->forgetGuards();
        $this->withToken($secret)->getJson('/api/v1/me/recipes')->assertOk();

        $this->forgetGuards();
        $this->withToken($session)->deleteJson('/api/v1/me/tokens/'.$created->json('data.id'))
            ->assertOk()->assertJsonPath('data.revoked', true);

        $this->forgetGuards();
        $this->withToken($secret)->getJson('/api/v1/me/recipes')->assertUnauthorized();
        $this->forgetGuards();
        $this->withToken($session)->getJson('/api/v1/me/tokens')->assertJsonCount(0, 'data');
        $this->assertDatabaseMissing('personal_access_tokens', ['name' => 'pat:Claude Desktop']);
    }

    public function test_token_creation_validates_abilities_and_limits(): void
    {
        $user = User::factory()->create();
        Sanctum::actingAs($user, ['*']);

        $this->postJson('/api/v1/me/tokens', ['name' => 'x', 'abilities' => ['admin']])
            ->assertUnprocessable()->assertJsonPath('error.code', 'validation_failed');
        $this->postJson('/api/v1/me/tokens', ['name' => 'x', 'abilities' => ['*']])->assertUnprocessable();
        $this->postJson('/api/v1/me/tokens', ['name' => 'x', 'abilities' => []])->assertUnprocessable();
        $this->postJson('/api/v1/me/tokens', ['abilities' => ['read']])->assertUnprocessable();
        $this->postJson('/api/v1/me/tokens', ['name' => 'x', 'abilities' => ['read'], 'expires_in_days' => 9999])
            ->assertUnprocessable();

        config(['api.personal_tokens.max_active' => 1]);
        $this->postJson('/api/v1/me/tokens', ['name' => 'one', 'abilities' => ['read']])->assertCreated();
        $this->postJson('/api/v1/me/tokens', ['name' => 'two', 'abilities' => ['read']])
            ->assertStatus(409)->assertJsonPath('error.code', 'conflict');
    }

    public function test_personal_access_tokens_cannot_manage_tokens_or_reach_admin_endpoints(): void
    {
        $admin = User::factory()->create(['is_admin' => true]);
        $pat = $admin->createToken('pat:script', ['read', 'write'])->plainTextToken;

        $this->withToken($pat)->postJson('/api/v1/me/tokens', ['name' => 'x', 'abilities' => ['read']])
            ->assertForbidden()->assertJsonPath('error.code', 'insufficient_scope');
        $this->forgetGuards();
        $this->withToken($pat)->getJson('/api/v1/me/tokens')->assertForbidden();
        $this->forgetGuards();
        $this->withToken($pat)->getJson('/api/v1/admin/users')
            ->assertForbidden()->assertJsonPath('error.code', 'insufficient_scope');

        $session = $admin->createToken('ios', ['*'])->plainTextToken;
        $this->forgetGuards();
        $this->withToken($session)->getJson('/api/v1/admin/users')->assertOk();
    }

    public function test_user_cannot_revoke_another_users_or_a_session_token(): void
    {
        $owner = User::factory()->create();
        $other = User::factory()->create();
        $foreign = $owner->createToken('pat:mine', ['read']);
        $session = $owner->createToken('ios', ['*']);
        $otherSession = $other->createToken('ios', ['*'])->plainTextToken;

        $this->withToken($otherSession)->deleteJson('/api/v1/me/tokens/'.$foreign->accessToken->getKey())->assertNotFound();
        $this->forgetGuards();
        $this->withToken($otherSession)->deleteJson('/api/v1/me/tokens/'.$session->accessToken->getKey())->assertNotFound();
        $this->forgetGuards();
        $this->withToken($otherSession)->deleteJson('/api/v1/me/tokens/not-a-number')->assertNotFound();
        $this->assertDatabaseHas('personal_access_tokens', ['id' => $foreign->accessToken->getKey()]);
    }

    public function test_read_scope_allows_reads_but_not_writes_and_write_scope_the_reverse(): void
    {
        $user = User::factory()->create();
        $read = $user->createToken('pat:r', ['read'])->plainTextToken;
        $write = $user->createToken('pat:w', ['write'])->plainTextToken;

        $this->withToken($read)->getJson('/api/v1/collections')->assertOk();
        $this->forgetGuards();
        $this->withToken($read)->postJson('/api/v1/collections', ['name' => 'Nope'])
            ->assertForbidden()
            ->assertJsonPath('error.code', 'insufficient_scope')
            ->assertJsonPath('error.details.required_scopes', ['write']);
        $this->forgetGuards();
        $this->withToken($write)->postJson('/api/v1/collections', ['name' => 'Fine'])->assertCreated();
        $this->forgetGuards();
        $this->withToken($write)->getJson('/api/v1/collections')
            ->assertForbidden()->assertJsonPath('error.details.required_scopes', ['read']);

        $this->assertDatabaseMissing('recipe_collections', ['name' => 'Nope']);
    }

    public function test_read_only_token_can_still_log_out(): void
    {
        $user = User::factory()->create();
        $read = $user->createToken('pat:r', ['read'])->plainTextToken;

        $this->withToken($read)->postJson('/api/v1/auth/logout')->assertOk();
        $this->forgetGuards();
        $this->withToken($read)->getJson('/api/v1/collections')->assertUnauthorized();
    }

    public function test_expired_and_suspended_tokens_are_rejected(): void
    {
        $user = User::factory()->create();
        $expired = $user->createToken('pat:old', ['read'], now()->subMinute())->plainTextToken;
        $this->withToken($expired)->getJson('/api/v1/me/recipes')->assertUnauthorized();

        $valid = $user->createToken('pat:ok', ['read'])->plainTextToken;
        $user->forceFill(['is_suspended' => true])->save();
        $this->forgetGuards();
        $this->withToken($valid)->getJson('/api/v1/me/recipes')->assertUnauthorized();
    }

    public function test_bearer_tokens_with_read_scope_let_owners_read_private_recipes_on_public_endpoints(): void
    {
        $camera = CameraModel::create(['manufacturer' => 'Fujifilm', 'name' => 'X-S20', 'slug' => 'x-s20']);
        $owner = User::factory()->create();
        $draft = Recipe::create(['user_id' => $owner->id, 'camera_model_id' => $camera->id, 'name' => 'Draft']);
        $read = $owner->createToken('pat:r', ['read'])->plainTextToken;
        $writeOnly = $owner->createToken('pat:w', ['write'])->plainTextToken;

        $this->getJson('/api/v1/recipes/'.$draft->id)->assertNotFound();
        $this->forgetGuards();
        $this->withToken('invalid-token')->getJson('/api/v1/recipes/'.$draft->id)->assertNotFound();
        $this->forgetGuards();
        $this->withToken($writeOnly)->getJson('/api/v1/recipes/'.$draft->id)->assertNotFound();
        $this->forgetGuards();
        $this->withToken($read)->getJson('/api/v1/recipes/'.$draft->id)
            ->assertOk()->assertJsonPath('data.name', 'Draft');
        $this->forgetGuards();
        $this->withToken($read)->getJson('/api/v1/recipes')->assertOk()->assertJsonCount(0, 'data');
    }

    public function test_collection_detail_is_owner_only(): void
    {
        $owner = User::factory()->create();
        $other = User::factory()->create();
        $collection = RecipeCollection::create(['user_id' => $owner->id, 'name' => 'Mine', 'sort_order' => 0]);

        Sanctum::actingAs($owner, ['read']);
        $this->getJson('/api/v1/collections/'.$collection->id)->assertOk()->assertJsonPath('data.name', 'Mine');

        Sanctum::actingAs($other, ['read']);
        $this->getJson('/api/v1/collections/'.$collection->id)->assertForbidden()
            ->assertJsonPath('error.code', 'forbidden');
    }

    public function test_rate_limits_return_the_error_envelope_per_bucket(): void
    {
        config(['api.rate_limits.read' => 2, 'api.rate_limits.write' => 1]);
        $user = User::factory()->create();
        $token = $user->createToken('pat:rw', ['read', 'write'])->plainTextToken;

        foreach ([1, 2] as $ignored) {
            $this->forgetGuards();
            $this->withToken($token)->getJson('/api/v1/collections')->assertOk();
        }
        $this->forgetGuards();
        $this->withToken($token)->getJson('/api/v1/collections')
            ->assertStatus(429)
            ->assertJsonPath('error.code', 'rate_limited')
            ->assertHeader('Retry-After');

        $this->forgetGuards();
        $this->withToken($token)->postJson('/api/v1/collections', ['name' => 'First'])->assertCreated();
        $this->forgetGuards();
        $this->withToken($token)->postJson('/api/v1/collections', ['name' => 'Second'])->assertStatus(429);
    }

    private function forgetGuards(): void
    {
        $this->app['auth']->forgetGuards();
    }
}
