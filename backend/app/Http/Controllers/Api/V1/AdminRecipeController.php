<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Resources\Api\V1\AdminRecipeResource;
use App\Models\Recipe;

class AdminRecipeController extends Controller
{
    public function show(Recipe $recipe): AdminRecipeResource
    {
        return new AdminRecipeResource($recipe->load([
            'cameraModel',
            'user',
            'categories',
            'tags',
            'settings',
            'images',
        ]));
    }
}
