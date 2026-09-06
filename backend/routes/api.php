<?php

use App\Http\Controllers\Api\V1\AuthController;
use App\Http\Controllers\Api\V1\CameraController;
use App\Http\Controllers\Api\V1\CategoryController;
use App\Http\Controllers\Api\V1\HealthController;
use App\Http\Controllers\Api\V1\ModerationReportController;
use App\Http\Controllers\Api\V1\ProfileController;
use App\Http\Controllers\Api\V1\RecipeCommentController;
use App\Http\Controllers\Api\V1\RecipeController;
use App\Http\Controllers\Api\V1\RecipeCopyController;
use App\Http\Controllers\Api\V1\RecipeEngagementController;
use App\Http\Controllers\Api\V1\RecipeImageController;
use App\Http\Controllers\Api\V1\SupportController;
use App\Http\Controllers\Api\V1\UserFollowController;
use App\Http\Controllers\Api\V1\UserSafetyController;
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
    Route::get('/support', SupportController::class)
        ->name('api.v1.support');
    Route::get('/recipes', [RecipeController::class, 'index'])
        ->name('api.v1.recipes.index');
    Route::get('/recipes/{recipe}/comments', [RecipeCommentController::class, 'index'])
        ->name('api.v1.recipes.comments.index');
    Route::post('/recipes/{recipe}/view', [RecipeEngagementController::class, 'view'])
        ->name('api.v1.recipes.view');
    Route::get('/recipes/{recipe}', [RecipeController::class, 'show'])
        ->name('api.v1.recipes.show');
    Route::get('/recipe-images/{recipeImage}', [RecipeImageController::class, 'show'])
        ->name('api.v1.recipe-images.show');

    Route::middleware(['auth.api:sanctum', 'active.account'])->group(function (): void {
        Route::post('/auth/logout', [AuthController::class, 'logout'])
            ->name('api.v1.auth.logout');
        Route::get('/me/profile', [ProfileController::class, 'mine'])
            ->name('api.v1.me.profile');
        Route::match(['patch', 'post'], '/me/profile', [ProfileController::class, 'update'])
            ->name('api.v1.me.profile.update');
        Route::post('/recipes', [RecipeController::class, 'store'])
            ->name('api.v1.recipes.store');
        Route::post('/recipes/{recipe}/comments', [RecipeCommentController::class, 'store'])
            ->name('api.v1.recipes.comments.store');
        Route::match(['patch', 'post'], '/recipes/{recipe}', [RecipeController::class, 'update'])
            ->name('api.v1.recipes.update');
        Route::delete('/recipes/{recipe}', [RecipeController::class, 'destroy'])
            ->name('api.v1.recipes.destroy');
        Route::delete('/comments/{comment}', [RecipeCommentController::class, 'destroy'])
            ->name('api.v1.comments.destroy');
        Route::post('/recipes/{recipe}/publish', [RecipeController::class, 'publish'])
            ->name('api.v1.recipes.publish');
        Route::post('/recipes/{recipe}/copy', [RecipeCopyController::class, 'store'])
            ->name('api.v1.recipes.copy');
        Route::post('/recipes/{recipe}/like', [RecipeEngagementController::class, 'like'])
            ->name('api.v1.recipes.like');
        Route::delete('/recipes/{recipe}/like', [RecipeEngagementController::class, 'unlike'])
            ->name('api.v1.recipes.unlike');
        Route::delete('/recipe-images/{recipeImage}', [RecipeImageController::class, 'destroy'])
            ->name('api.v1.recipe-images.destroy');
        Route::post('/recipes/{recipe}/reports', [ModerationReportController::class, 'storeRecipe'])
            ->name('api.v1.recipes.reports.store');
        Route::post('/comments/{comment}/reports', [ModerationReportController::class, 'storeComment'])
            ->name('api.v1.comments.reports.store');
        Route::post('/recipe-images/{recipeImage}/reports', [ModerationReportController::class, 'storeImage'])
            ->name('api.v1.recipe-images.reports.store');
        Route::post('/profiles/{username}/reports', [ModerationReportController::class, 'storeProfile'])
            ->name('api.v1.profiles.reports.store');
        Route::post('/users/{user}/reports', [ModerationReportController::class, 'storeUser'])
            ->name('api.v1.users.reports.store');
        Route::post('/profiles/{username}/block', [UserSafetyController::class, 'block'])
            ->name('api.v1.profiles.block');
        Route::delete('/profiles/{username}/block', [UserSafetyController::class, 'unblock'])
            ->name('api.v1.profiles.unblock');
        Route::post('/profiles/{username}/follow', [UserFollowController::class, 'store'])
            ->name('api.v1.profiles.follow');
        Route::delete('/profiles/{username}/follow', [UserFollowController::class, 'destroy'])
            ->name('api.v1.profiles.unfollow');
        Route::post('/users/{user}/block', [UserSafetyController::class, 'blockUser'])
            ->name('api.v1.users.block');
        Route::delete('/users/{user}/block', [UserSafetyController::class, 'unblockUser'])
            ->name('api.v1.users.unblock');
        Route::get('/admin/reports', [ModerationReportController::class, 'index'])
            ->name('api.v1.admin.reports.index');
        Route::patch('/admin/reports/{report}', [ModerationReportController::class, 'update'])
            ->name('api.v1.admin.reports.update');
    });
});
