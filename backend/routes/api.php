<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\CameraController;
use App\Http\Controllers\Api\V1\CategoryController;
use App\Http\Controllers\Api\V1\HealthController;
use App\Http\Controllers\Api\V1\ProfileController;
use App\Http\Controllers\Api\V1\RecipeController;
use App\Http\Controllers\Api\V1\RecipeImageController;
use Illuminate\Support\Facades\Route;

Route::prefix('v1')->group(function (): void {
    Route::get('/health', HealthController::class)->name('api.v1.health');
    Route::post('/auth/apple', [AuthController::class, 'apple'])
        ->name('api.v1.auth.apple');
    Route::get('/profiles/{username}', [ProfileController::class, 'show'])
        ->name('api.v1.profiles.show');
    Route::get('/cameras', [CameraController::class, 'index'])
        ->name('api.v1.cameras.index');
    Route::get('/cameras/{camera}/capabilities', [CameraController::class, 'capabilities'])
        ->name('api.v1.cameras.capabilities');
    Route::get('/cameras/{camera}', [CameraController::class, 'show'])
        ->name('api.v1.cameras.show');
    Route::get('/categories', [CategoryController::class, 'index'])
        ->name('api.v1.categories.index');
    Route::get('/recipes', [RecipeController::class, 'index'])
        ->name('api.v1.recipes.index');
    Route::get('/recipes/{recipe}', [RecipeController::class, 'show'])
        ->name('api.v1.recipes.show');
    Route::get('/recipe-images/{recipeImage}', [RecipeImageController::class, 'show'])
        ->name('api.v1.recipe-images.show');

    Route::middleware('auth.api:sanctum')->group(function (): void {
        Route::post('/auth/logout', [AuthController::class, 'logout'])
            ->name('api.v1.auth.logout');
        Route::get('/me/profile', [ProfileController::class, 'mine'])
            ->name('api.v1.me.profile');
        Route::match(['patch', 'post'], '/me/profile', [ProfileController::class, 'update'])
            ->name('api.v1.me.profile.update');
        Route::post('/recipes', [RecipeController::class, 'store'])
            ->name('api.v1.recipes.store');
        Route::match(['patch', 'post'], '/recipes/{recipe}', [RecipeController::class, 'update'])
            ->name('api.v1.recipes.update');
        Route::delete('/recipes/{recipe}', [RecipeController::class, 'destroy'])
            ->name('api.v1.recipes.destroy');
        Route::post('/recipes/{recipe}/publish', [RecipeController::class, 'publish'])
            ->name('api.v1.recipes.publish');
        Route::delete('/recipe-images/{recipeImage}', [RecipeImageController::class, 'destroy'])
            ->name('api.v1.recipe-images.destroy');
    });
});
