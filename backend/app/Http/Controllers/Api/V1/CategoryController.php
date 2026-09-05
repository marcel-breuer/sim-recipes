<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Resources\Api\V1\CategoryResource;
use App\Models\Category;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class CategoryController
{
    public function index(): AnonymousResourceCollection
    {
        return CategoryResource::collection(Category::query()->orderBy('name')->get());
    }
}
