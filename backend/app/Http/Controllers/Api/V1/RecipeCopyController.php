<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\Api\V1\RecipeResource;
use App\Models\Recipe;
use App\Models\User;
use App\Services\Recipes\RecipeCopyService;
use Illuminate\Http\Request;

class RecipeCopyController extends Controller
{
    public function store(
        Request $request,
        Recipe $recipe,
        RecipeCopyService $copyService,
    ): RecipeResource {
        abort_unless($recipe->status === Recipe::STATUS_PUBLISHED, 404);
        $user = $request->user();
        abort_unless($user instanceof User, 401);

        $copy = $copyService->copy($recipe, $user);

        return new RecipeResource(
            Recipe::query()
                ->with(['cameraModel', 'user', 'categories', 'tags', 'settings', 'images', 'provenance'])
                ->findOrFail($copy->getKey()),
        );
    }
}
