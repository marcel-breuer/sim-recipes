<?php

namespace Tests\Unit;

use App\Support\Observability\DatabaseQueryMetrics;
use App\Support\Observability\QueueExecutionMetrics;
use Illuminate\Contracts\Queue\Job;
use Illuminate\Support\Facades\Log;
use Mockery;
use Psr\Log\LoggerInterface;
use Tests\TestCase;

class QueueExecutionMetricsTest extends TestCase
{
    public function test_completed_job_logs_wait_runtime_and_database_totals_without_payload(): void
    {
        $databaseMetrics = app(DatabaseQueryMetrics::class);
        $metrics = new QueueExecutionMetrics($databaseMetrics);
        $job = Mockery::mock(Job::class);
        $job->shouldReceive('payload')->once()->andReturn(['createdAt' => microtime(true) - 0.05]);
        $job->shouldReceive('resolveName')->once()->andReturn('App\\Jobs\\ExampleJob');
        $job->shouldReceive('getQueue')->once()->andReturn('default');
        $job->shouldReceive('attempts')->once()->andReturn(2);
        $logger = Mockery::mock(LoggerInterface::class);
        $logger->shouldReceive('info')
            ->once()
            ->with('queue.job.completed', Mockery::on(function (array $context): bool {
                $this->assertSame([
                    'job',
                    'queue',
                    'attempt',
                    'queue_wait_ms',
                    'outcome',
                    'duration_ms',
                    'db_query_count',
                    'db_duration_ms',
                ], array_keys($context));
                $this->assertSame('App\\Jobs\\ExampleJob', $context['job']);
                $this->assertSame('default', $context['queue']);
                $this->assertSame(2, $context['attempt']);
                $this->assertSame('completed', $context['outcome']);
                $this->assertGreaterThanOrEqual(0, $context['queue_wait_ms']);
                $this->assertGreaterThanOrEqual(0, $context['duration_ms']);
                $this->assertSame(1, $context['db_query_count']);
                $this->assertSame(3.5, $context['db_duration_ms']);

                return true;
            }));
        Log::shouldReceive('channel')->once()->with('stderr')->andReturn($logger);

        $metrics->start($job);
        $databaseMetrics->record(3.5);
        $metrics->finish('completed');
    }
}
