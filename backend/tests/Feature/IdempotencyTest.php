<?php

namespace Tests\Feature;

use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Laravel\Sanctum\Sanctum;
use Tests\TestCase;

class IdempotencyTest extends TestCase
{
    use RefreshDatabase;

    public function test_retrying_a_create_with_the_same_key_returns_the_original_result_without_duplicates(): void
    {
        $camera = CameraModel::create(['manufacturer' => 'Fujifilm', 'name' => 'X-S20', 'slug' => 'x-s20']);
        Sanctum::actingAs(User::factory()->create(), ['*']);
        $payload = ['name' => 'Once', 'camera_model_id' => $camera->id];
        $headers = ['Idempotency-Key' => 'draft-save-0001'];

        $first = $this->postJson('/api/v1/recipes', $payload, $headers)->assertOk();
        $second = $this->postJson('/api/v1/recipes', $payload, $headers)
            ->assertOk()
            ->assertHeader('Idempotent-Replayed', 'true');

        self::assertSame($first->json('data.id'), $second->json('data.id'));
        self::assertSame(1, Recipe::query()->where('name', 'Once')->count());
    }

    public function test_reusing_a_key_with_a_different_payload_is_rejected(): void
    {
        $camera = CameraModel::create(['manufacturer' => 'Fujifilm', 'name' => 'X-S20', 'slug' => 'x-s20']);
        Sanctum::actingAs(User::factory()->create(), ['*']);
        $headers = ['Idempotency-Key' => 'draft-save-0002'];

        $this->postJson('/api/v1/recipes', ['name' => 'A', 'camera_model_id' => $camera->id], $headers)->assertOk();
        $this->postJson('/api/v1/recipes', ['name' => 'B', 'camera_model_id' => $camera->id], $headers)
            ->assertUnprocessable()
            ->assertJsonPath('error.code', 'idempotency_key_reused');

        self::assertSame(0, Recipe::query()->where('name', 'B')->count());
    }

    public function test_failed_requests_are_not_stored_and_keys_are_scoped_per_user(): void
    {
        $camera = CameraModel::create(['manufacturer' => 'Fujifilm', 'name' => 'X-S20', 'slug' => 'x-s20']);
        $headers = ['Idempotency-Key' => 'shared-key-0003'];

        Sanctum::actingAs(User::factory()->create(), ['*']);
        $this->postJson('/api/v1/collections', ['name' => ''], $headers)->assertUnprocessable();
        $this->postJson('/api/v1/collections', ['name' => 'Fixed'], $headers)->assertCreated();

        Sanctum::actingAs(User::factory()->create(), ['*']);
        $this->postJson('/api/v1/collections', ['name' => 'Other user'], $headers)
            ->assertCreated()
            ->assertHeaderMissing('Idempotent-Replayed');
        self::assertNotNull($camera);
    }

    public function test_malformed_keys_are_rejected_and_requests_without_a_key_are_unchanged(): void
    {
        Sanctum::actingAs(User::factory()->create(), ['*']);

        $this->postJson('/api/v1/collections', ['name' => 'X'], ['Idempotency-Key' => 'short'])
            ->assertUnprocessable()
            ->assertJsonPath('error.code', 'invalid_idempotency_key');
        $this->postJson('/api/v1/collections', ['name' => 'One'])->assertCreated();
        $this->postJson('/api/v1/collections', ['name' => 'Two'])->assertCreated();
        $this->postJson('/api/v1/collections', ['name' => 'One'])
            ->assertUnprocessable()
            ->assertJsonPath('error.code', 'validation_failed');
    }
}
