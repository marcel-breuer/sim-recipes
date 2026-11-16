<?php

namespace App\Providers;

use App\Services\Auth\AppleIdentityTokenVerifier;
use App\Services\Auth\AppleIdentityTokenVerifierContract;
use App\Services\Recipes\DefaultPopularityRanking;
use App\Services\Recipes\PopularityRanking;
use App\Support\Observability\DatabaseQueryMetrics;
use App\Support\Observability\QueueExecutionMetrics;
use Illuminate\Cache\RateLimiting\Limit;
use Illuminate\Database\Events\QueryExecuted;
use Illuminate\Http\Request;
use Illuminate\Queue\Events\JobExceptionOccurred;
use Illuminate\Queue\Events\JobProcessed;
use Illuminate\Queue\Events\JobProcessing;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Queue;
use Illuminate\Support\Facades\RateLimiter;
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
        $this->configureRateLimiting();

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

    private function configureRateLimiting(): void
    {
        $identity = static function (Request $request): string {
            $token = $request->bearerToken();

            return $token !== null && $token !== '' ? 'token:'.hash('sha256', $token) : 'ip:'.$request->ip();
        };

        RateLimiter::for('api', static fn (Request $request): Limit => $request->isMethodSafe()
            ? Limit::perMinute((int) config('api.rate_limits.read'))->by('read:'.$identity($request))
            : Limit::perMinute((int) config('api.rate_limits.write'))->by('write:'.$identity($request)));

        RateLimiter::for('api-auth', static fn (Request $request): Limit => Limit::perMinute(
            (int) config('api.rate_limits.auth'),
        )->by('auth:ip:'.$request->ip()));

        RateLimiter::for('mcp', static fn (Request $request): Limit => Limit::perMinute(
            (int) config('api.rate_limits.mcp'),
        )->by('mcp:'.$identity($request)));
    }
}
