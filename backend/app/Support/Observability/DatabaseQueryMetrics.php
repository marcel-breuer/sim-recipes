<?php

namespace App\Support\Observability;

final class DatabaseQueryMetrics
{
    private int $queryCount = 0;

    private float $durationMilliseconds = 0.0;

    public function record(int|float $durationMilliseconds): void
    {
        $this->queryCount++;
        $this->durationMilliseconds += max(0, $durationMilliseconds);
    }

    public function reset(): void
    {
        $this->queryCount = 0;
        $this->durationMilliseconds = 0.0;
    }

    /**
     * @return array{query_count: int, duration_ms: float}
     */
    public function snapshot(): array
    {
        return [
            'query_count' => $this->queryCount,
            'duration_ms' => round($this->durationMilliseconds, 2),
        ];
    }
}
