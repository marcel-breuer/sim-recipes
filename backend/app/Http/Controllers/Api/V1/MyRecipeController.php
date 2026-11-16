<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\IndexMyRecipeRequest;
use App\Http\Resources\Api\V1\RecipeResource;
use App\Models\Recipe;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

class MyRecipeController extends Controller
{
    /**
     * The authenticated user's personal recipe library: private drafts,
     * published recipes and copies of community recipes, newest first.
     */
    public function index(IndexMyRecipeRequest $request): AnonymousResourceCollection
    {
        $filters = $request->validated();

        $query = Recipe::query()
            ->where('user_id', $request->user()->getKey())
            ->where('is_hidden', false)
            ->with(['cameraModel', 'user.profile', 'categories', 'tags', 'settings', 'images', 'provenance'])
            ->orderByDesc('created_at')
            ->orderByDesc('id');

        if (filled($filters['status'] ?? null)) {
            $query->where('status', $filters['status']);
        }

        if (filled($filters['camera_model_id'] ?? null)) {
            $query->where('camera_model_id', $filters['camera_model_id']);
        }

        if (filled($filters['search'] ?? null)) {
            $pattern = '%'.mb_strtolower(trim((string) $filters['search'])).'%';
            $query->where(function (Builder $searchQuery) use ($pattern): void {
                $searchQuery
                    ->whereRaw('LOWER(name) LIKE ?', [$pattern])
                    ->orWhereRaw('LOWER(description) LIKE ?', [$pattern])
                    ->orWhereRaw('LOWER(recommendation) LIKE ?', [$pattern]);
            });
        }

        return RecipeResource::collection($query->cursorPaginate(
            perPage: $filters['per_page'] ?? config('api.pagination.default_per_page'),
        ));
    }
}
