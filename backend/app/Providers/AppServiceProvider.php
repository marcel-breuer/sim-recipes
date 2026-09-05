<?php

namespace App\Providers;

use App\Services\Auth\AppleIdentityTokenVerifier;
use App\Services\Auth\AppleIdentityTokenVerifierContract;
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
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        //
    }
}
