<?php

namespace Tests\Feature;

use App\Models\User;
use App\Services\Auth\AppleIdentity;
use App\Services\Auth\AppleIdentityTokenVerifierContract;
use App\Services\Auth\InvalidAppleIdentityToken;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Route;
use Tests\TestCase;

class AuthenticationTest extends TestCase
{
    use RefreshDatabase;

    public function test_apple_login_creates_a_user_and_returns_a_sanctum_token(): void
    {
        $this->fakeAppleIdentity();

        $response = $this->postJson('/api/v1/auth/apple', [
            'identity_token' => 'valid-token',
            'name' => 'Marcel Breuer',
        ]);

        $response->assertOk()
            ->assertJsonStructure([
                'data' => [
                    'token',
                    'expires_at',
                    'user' => ['id', 'name', 'email'],
                ],
            ])
            ->assertJsonPath('data.user.name', 'Marcel Breuer')
            ->assertJsonPath('data.user.email', 'marcel@example.test');

        $this->assertDatabaseHas('users', [
            'apple_subject' => 'apple-subject-1',
            'email' => 'marcel@example.test',
            'name' => 'Marcel Breuer',
        ]);
        $this->assertDatabaseCount('personal_access_tokens', 1);
    }

    public function test_apple_login_resolves_existing_user_without_creating_a_duplicate(): void
    {
        $user = User::factory()->create([
            'name' => 'Original Name',
            'apple_subject' => 'apple-subject-1',
        ]);
        $this->fakeAppleIdentity();

        $this->postJson('/api/v1/auth/apple', [
            'identity_token' => 'valid-token',
            'name' => 'Ignored Name',
        ])->assertOk();

        $this->assertDatabaseCount('users', 1);
        $this->assertDatabaseHas('users', [
            'id' => $user->id,
            'name' => 'Original Name',
            'email' => 'marcel@example.test',
        ]);
    }

    public function test_invalid_apple_credentials_are_rejected(): void
    {
        $this->app->instance(
            AppleIdentityTokenVerifierContract::class,
            new class implements AppleIdentityTokenVerifierContract
            {
                public function verify(string $identityToken): AppleIdentity
                {
                    throw new InvalidAppleIdentityToken;
                }
            },
        );

        $this->postJson('/api/v1/auth/apple', [
            'identity_token' => 'expired-token',
        ])->assertUnauthorized()
            ->assertJsonPath('error.code', 'unauthenticated');

        $this->assertDatabaseCount('users', 0);
    }

    public function test_sanctum_tokens_protect_authenticated_mutations_and_logout_revokes_current_token(): void
    {
        $user = User::factory()->create();
        Route::middleware('auth.api:sanctum')->post('/api/v1/protected-test-route', function (): array {
            return ['status' => 'ok'];
        });
        $token = $user->createToken('test-token');

        $this->postJson('/api/v1/protected-test-route')
            ->assertUnauthorized();

        $this->withToken($token->plainTextToken)
            ->postJson('/api/v1/protected-test-route')
            ->assertOk()
            ->assertJsonPath('status', 'ok');

        $this->withToken($token->plainTextToken)
            ->postJson('/api/v1/auth/logout')
            ->assertOk()
            ->assertJsonPath('data.logged_out', true);

        $this->withToken($token->plainTextToken)
            ->postJson('/api/v1/protected-test-route')
            ->assertUnauthorized();

        $this->assertDatabaseCount('personal_access_tokens', 0);
    }

    private function fakeAppleIdentity(): void
    {
        $this->app->instance(
            AppleIdentityTokenVerifierContract::class,
            new class implements AppleIdentityTokenVerifierContract
            {
                public function verify(string $identityToken): AppleIdentity
                {
                    return new AppleIdentity(
                        subject: 'apple-subject-1',
                        email: 'marcel@example.test',
                    );
                }
            },
        );
    }
}
