<?php

namespace Tests\Feature;

use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Facades\Log;
use Mockery;
use Psr\Log\LoggerInterface;
use Tests\TestCase;

class ApiRequestObservabilityTest extends TestCase
{
    use RefreshDatabase;

    public function test_api_request_logs_route_timings_and_query_totals_without_request_data(): void
    {
        $loggedContext = null;
        $logger = Mockery::mock(LoggerInterface::class);
        $logger->shouldReceive('info')
            ->once()
            ->with('api.request.completed', Mockery::on(function (array $context) use (&$loggedContext): bool {
                $loggedContext = $context;

                return true;
            }));
        Log::shouldReceive('channel')->once()->with('stderr')->andReturn($logger);
        Log::shouldReceive('withContext')->once()->with(Mockery::type('array'));

        $this->withoutExceptionHandling();
        $this->getJson('/api/v1/cameras')->assertOk();

        $this->assertIsArray($loggedContext);
        $this->assertSame([
            'route',
            'method',
            'status',
            'duration_ms',
            'db_query_count',
            'db_duration_ms',
        ], array_keys($loggedContext));
        $this->assertSame('api.v1.cameras.index', $loggedContext['route']);
        $this->assertSame('GET', $loggedContext['method']);
        $this->assertSame(200, $loggedContext['status']);
        $this->assertGreaterThan(0, $loggedContext['db_query_count']);
        $this->assertGreaterThanOrEqual(0, $loggedContext['db_duration_ms']);
        $this->assertGreaterThan(0, $loggedContext['duration_ms']);
    }

    public function test_recipe_feed_metrics_use_only_the_allowlisted_feed_dimension(): void
    {
        $loggedContext = null;
        $logger = Mockery::mock(LoggerInterface::class);
        $logger->shouldReceive('info')
            ->once()
            ->with('api.request.completed', Mockery::on(function (array $context) use (&$loggedContext): bool {
                $loggedContext = $context;

                return true;
            }));
        Log::shouldReceive('channel')->once()->with('stderr')->andReturn($logger);
        Log::shouldReceive('withContext')->once()->with(Mockery::type('array'));

        $this->withoutExceptionHandling();
        $this->getJson('/api/v1/recipes?feed=newest')->assertOk();

        $this->assertIsArray($loggedContext);
        $this->assertSame('api.v1.recipes.index', $loggedContext['route']);
        $this->assertSame('newest', $loggedContext['feed']);
        $this->assertArrayNotHasKey('query', $loggedContext);
        $this->assertArrayNotHasKey('path', $loggedContext);
    }

    public function test_not_found_requests_log_the_resolved_http_status(): void
    {
        $loggedContext = null;
        $logger = Mockery::mock(LoggerInterface::class);
        $logger->shouldReceive('info')
            ->once()
            ->with('api.request.completed', Mockery::on(function (array $context) use (&$loggedContext): bool {
                $loggedContext = $context;

                return true;
            }));
        Log::shouldReceive('channel')->once()->with('stderr')->andReturn($logger);
        Log::shouldReceive('withContext')->once()->with(Mockery::type('array'));

        $this->getJson('/api/v1/cameras/not-a-camera')->assertNotFound();

        $this->assertIsArray($loggedContext);
        $this->assertSame(404, $loggedContext['status']);
    }
}
