<?php

namespace App\Providers;

use App\Services\Auth\AppleIdentityTokenVerifier;
use App\Services\Auth\AppleIdentityTokenVerifierContract;
use App\Services\Recipes\DefaultPopularityRanking;
use App\Services\Recipes\PopularityRanking;
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
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
