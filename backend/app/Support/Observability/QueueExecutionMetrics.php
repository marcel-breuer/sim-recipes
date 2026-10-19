<?php

namespace App\Support\Observability;

use Illuminate\Contracts\Queue\Job;
use Illuminate\Support\Facades\Log;

final class QueueExecutionMetrics
{
    private ?int $startedAtNanoseconds = null;

    /** @var array{job: string, queue: string, attempt: int, queue_wait_ms: float|null}|null */
    private ?array $context = null;

    public function __construct(private readonly DatabaseQueryMetrics $databaseMetrics) {}

    public function start(Job $job): void
    {
        $payload = $job->payload();
        $createdAt = $payload['createdAt'] ?? null;
        $queueWaitMilliseconds = is_numeric($createdAt)
            ? round(max(0, (microtime(true) - (float) $createdAt) * 1000), 2)
            : null;

        $this->databaseMetrics->reset();
        $this->startedAtNanoseconds = hrtime(true);
        $this->context = [
            'job' => $job->resolveName(),
            'queue' => $job->getQueue(),
            'attempt' => $job->attempts(),
            'queue_wait_ms' => $queueWaitMilliseconds,
        ];
    }

    public function finish(string $outcome): void
    {
        if ($this->startedAtNanoseconds === null || $this->context === null) {
            return;
        }

        $durationMilliseconds = round((hrtime(true) - $this->startedAtNanoseconds) / 1_000_000, 2);
        $metrics = $this->databaseMetrics->snapshot();
        $context = [
            ...$this->context,
            'outcome' => $outcome,
            'duration_ms' => $durationMilliseconds,
            'db_query_count' => $metrics['query_count'],
            'db_duration_ms' => $metrics['duration_ms'],
        ];

        if ($outcome === 'completed') {
            Log::channel('stderr')->info('queue.job.completed', $context);
        } else {
            Log::channel('stderr')->warning('queue.job.attempt_failed', $context);
        }

        $this->startedAtNanoseconds = null;
        $this->context = null;
    }
}
