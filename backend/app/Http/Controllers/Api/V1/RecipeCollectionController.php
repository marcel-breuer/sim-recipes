<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\ReorderRecipeCollectionsRequest;
use App\Http\Requests\Api\V1\StoreRecipeCollectionRequest;
use App\Http\Requests\Api\V1\UpdateRecipeCollectionRequest;
use App\Http\Resources\Api\V1\RecipeCollectionResource;
use App\Models\Recipe;
use App\Models\RecipeCollection;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

class RecipeCollectionController extends Controller
{
    public function index(): AnonymousResourceCollection
    {
        $collections = RecipeCollection::query()
            ->where('user_id', request()->user()->getKey())
            ->with(['recipes' => fn ($query) => $query->with('cameraModel')])
            ->orderBy('sort_order')
            ->orderBy('id')
            ->get();

        return RecipeCollectionResource::collection($collections);
    }

    public function store(StoreRecipeCollectionRequest $request): RecipeCollectionResource
    {
        $collection = RecipeCollection::query()->create([
            'user_id' => $request->user()->getKey(),
            'name' => $request->string('name')->toString(),
            'is_public' => $request->boolean('is_public'),
            'sort_order' => (int) RecipeCollection::query()
                ->where('user_id', $request->user()->getKey())
                ->max('sort_order') + 1,
        ]);

        return new RecipeCollectionResource($collection->load(['recipes' => fn ($query) => $query->with('cameraModel')]));
    }

    public function update(
        UpdateRecipeCollectionRequest $request,
        RecipeCollection $collection,
    ): RecipeCollectionResource {
        Gate::authorize('manage', $collection);
        $collection->fill($request->validated());
        $collection->save();

        return new RecipeCollectionResource($collection->load(['recipes' => fn ($query) => $query->with('cameraModel')]));
    }

    public function destroy(RecipeCollection $collection): JsonResponse
    {
        Gate::authorize('manage', $collection);
        $collection->delete();

        return response()->json(['data' => ['deleted' => true]]);
    }

    public function addRecipe(RecipeCollection $collection, Recipe $recipe): RecipeCollectionResource
    {
        Gate::authorize('manage', $collection);
        Gate::authorize('view', $recipe);

        $sortOrder = (int) $collection->recipes()->max('recipe_collection_recipe.sort_order') + 1;
        $collection->recipes()->syncWithoutDetaching([$recipe->getKey() => ['sort_order' => $sortOrder]]);

        return new RecipeCollectionResource($collection->load(['recipes' => fn ($query) => $query->with('cameraModel')]));
    }

    public function removeRecipe(RecipeCollection $collection, Recipe $recipe): RecipeCollectionResource
    {
        Gate::authorize('manage', $collection);
        $collection->recipes()->detach($recipe->getKey());

        return new RecipeCollectionResource($collection->load(['recipes' => fn ($query) => $query->with('cameraModel')]));
    }

    public function reorder(ReorderRecipeCollectionsRequest $request): AnonymousResourceCollection
    {
        $collectionIDs = $request->validated('collection_ids');
        $collections = RecipeCollection::query()
            ->where('user_id', $request->user()->getKey())
            ->whereIn('id', $collectionIDs)
            ->get()
            ->keyBy('id');

        abort_if($collections->count() !== count($collectionIDs), 422, 'The collection order contains an unavailable collection.');

        DB::transaction(function () use ($collectionIDs, $collections): void {
            foreach ($collectionIDs as $index => $collectionID) {
                $collections->get($collectionID)->update(['sort_order' => $index]);
            }
        });

        return RecipeCollectionResource::collection(
            RecipeCollection::query()
                ->where('user_id', $request->user()->getKey())
                ->with(['recipes' => fn ($query) => $query->with('cameraModel')])
                ->orderBy('sort_order')
                ->orderBy('id')
                ->get(),
        );
    }
}
