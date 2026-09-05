<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\HealthController;
use App\Http\Controllers\Api\V1\ProfileController;
use App\Http\Controllers\Api\V1\RecipeController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function (): void {
    Route::get('/health', HealthController::class)->name('api.v1.health');
    Route::post('/auth/apple', [AuthController::class, 'apple'])
        ->name('api.v1.auth.apple');
    Route::get('/profiles/{username}', [ProfileController::class, 'show'])
        ->name('api.v1.profiles.show');
    Route::get('/recipes/{recipe}', [RecipeController::class, 'show'])
        ->name('api.v1.recipes.show');

    Route::middleware('auth.api:sanctum')->group(function (): void {
        Route::post('/auth/logout', [AuthController::class, 'logout'])
            ->name('api.v1.auth.logout');
        Route::get('/me/profile', [ProfileController::class, 'mine'])
            ->name('api.v1.me.profile');
        Route::match(['patch', 'post'], '/me/profile', [ProfileController::class, 'update'])
            ->name('api.v1.me.profile.update');
        Route::post('/recipes', [RecipeController::class, 'store'])
            ->name('api.v1.recipes.store');
        Route::patch('/recipes/{recipe}', [RecipeController::class, 'update'])
            ->name('api.v1.recipes.update');
        Route::delete('/recipes/{recipe}', [RecipeController::class, 'destroy'])
            ->name('api.v1.recipes.destroy');
        Route::post('/recipes/{recipe}/publish', [RecipeController::class, 'publish'])
            ->name('api.v1.recipes.publish');
    });
});
