<?php

namespace App\Providers;

use App\Services\Auth\AppleIdentityTokenVerifier;
use App\Services\Auth\AppleIdentityTokenVerifierContract;
use App\Services\Recipes\DefaultPopularityRanking;
use App\Services\Recipes\PopularityRanking;
use App\Support\Observability\DatabaseQueryMetrics;
use App\Support\Observability\QueueExecutionMetrics;
use Illuminate\Database\Events\QueryExecuted;
use Illuminate\Queue\Events\JobExceptionOccurred;
use Illuminate\Queue\Events\JobProcessed;
use Illuminate\Queue\Events\JobProcessing;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    public function register(): void
    {
        $this->app->bind(
            AppleIdentityTokenVerifierContract::class,
            AppleIdentityTokenVerifier::class,
        );
        $this->app->bind(PopularityRanking::class, DefaultPopularityRanking::class);
        $this->app->scoped(DatabaseQueryMetrics::class);
        $this->app->scoped(QueueExecutionMetrics::class);
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        DB::listen(static function (QueryExecuted $query): void {
            app(DatabaseQueryMetrics::class)->record($query->time);
        });

        Queue::before(static function (JobProcessing $event): void {
            app(DatabaseQueryMetrics::class)->reset();
            app(QueueExecutionMetrics::class)->start($event->job);
        });

        Queue::after(static function (JobProcessed $event): void {
            app(QueueExecutionMetrics::class)->finish('completed');
        });

        Queue::exceptionOccurred(static function (JobExceptionOccurred $event): void {
            app(QueueExecutionMetrics::class)->finish('attempt_failed');
        });
    }
}
