<?php

namespace Tests\Feature;

use Illuminate\Support\Facades\Route;
use Tests\TestCase;

class HealthEndpointTest extends TestCase
{
    public function test_the_versioned_health_endpoint_returns_a_resource(): void
    {
        $this->withHeader('X-Request-ID', 'health-test-1')
            ->getJson('/api/v1/health')
            ->assertOk()
            ->assertHeader('X-Request-ID', 'health-test-1')
            ->assertJsonPath('data.service', 'sim-recipes-api')
            ->assertJsonPath('data.status', 'ok')
            ->assertJsonPath('data.version', 'v1');
    }

    public function test_unknown_api_routes_use_the_error_contract(): void
    {
        $this->getJson('/api/v1/not-a-route')
            ->assertNotFound()
            ->assertJsonStructure([
                'error' => ['code', 'message'],
            ])
            ->assertJsonPath('error.code', 'not_found');
    }

    public function test_api_authentication_boundary_returns_a_json_error(): void
    {
        Route::middleware('auth.api')->get('/api/v1/protected-test-route', function (): array {
            return ['status' => 'ok'];
        });

        $this->getJson('/api/v1/protected-test-route')
            ->assertUnauthorized()
            ->assertJsonPath('error.code', 'unauthenticated');
    }
}
