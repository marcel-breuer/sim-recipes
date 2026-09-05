<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\IndexRecipeRequest;
use App\Http\Requests\Api\V1\StoreRecipeRequest;
use App\Http\Requests\Api\V1\UpdateRecipeRequest;
use App\Http\Resources\Api\V1\RecipeResource;
use App\Models\CameraCapability;
use App\Models\Recipe;
use App\Models\RecipeSetting;
use App\Models\Tag;
use App\Services\Recipes\PopularityRanking;
use App\Services\Recipes\RecipeCapabilityValidator;
use App\Services\Recipes\RecipeImageStorage;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Str;

class RecipeController extends Controller
{
    public function index(
        IndexRecipeRequest $request,
        PopularityRanking $popularityRanking,
    ): AnonymousResourceCollection {
        $filters = $request->validated();
        $query = Recipe::query()
            ->where('status', Recipe::STATUS_PUBLISHED)
            ->with([
                'cameraModel',
                'user',
                'categories',
                'tags',
                'settings',
                'images',
            ]);

        $this->applyFilters($query, $filters);

        if (($filters['feed'] ?? 'popular') === 'newest') {
            $query
                ->orderByDesc('published_at')
                ->orderByDesc('id');
        } else {
            $popularityRanking->apply($query);
        }

        return RecipeResource::collection($query->paginate(
            perPage: $filters['per_page'] ?? config('api.pagination.default_per_page'),
        ));
    }

    public function show(Recipe $recipe): RecipeResource
    {
        abort_unless($this->canView($recipe), 404);

        return new RecipeResource($this->recipeQuery()->findOrFail($recipe->getKey()));
    }

    public function store(
        StoreRecipeRequest $request,
        RecipeCapabilityValidator $capabilityValidator,
        RecipeImageStorage $imageStorage,
    ): RecipeResource {
        $data = $request->validated();
        $settings = $data['settings'] ?? [];
        $capabilityValidator->validate($data['camera_model_id'], $settings);

        $recipe = DB::transaction(function () use ($request, $data, $settings, $imageStorage): Recipe {
            $recipe = Recipe::create([
                'user_id' => $request->user()->getKey(),
                'camera_model_id' => $data['camera_model_id'],
                'name' => $data['name'],
                'description' => $data['description'] ?? null,
                'recommendation' => $data['recommendation'] ?? null,
                'lens' => $data['lens'] ?? null,
            ]);
            $this->syncRelations($recipe, $data, $settings);
            $imageStorage->store($recipe, $request->file('images', []));

            return $recipe;
        });

        return new RecipeResource($this->recipeQuery()->findOrFail($recipe->getKey()));
    }

    public function update(
        UpdateRecipeRequest $request,
        Recipe $recipe,
        RecipeCapabilityValidator $capabilityValidator,
        RecipeImageStorage $imageStorage,
    ): RecipeResource {
        Gate::authorize('update', $recipe);
        $data = $request->validated();
        $cameraModelID = $data['camera_model_id'] ?? $recipe->camera_model_id;
        $settings = $data['settings'] ?? RecipeSetting::query()
            ->where('recipe_id', $recipe->getKey())
            ->get()
            ->map(static fn (RecipeSetting $setting): array => [
                'setting_key' => $setting->getAttribute('setting_key'),
                'value' => $setting->getAttribute('value'),
            ])->all();
        $capabilityValidator->validate($cameraModelID, $settings);

        DB::transaction(function () use ($request, $data, $recipe, $cameraModelID, $settings, $imageStorage): void {
            $attributes = ['camera_model_id' => $cameraModelID];
            foreach (['name', 'description', 'recommendation', 'lens'] as $field) {
                if (array_key_exists($field, $data)) {
                    $attributes[$field] = $data[$field];
                }
            }
            $recipe->fill($attributes);
            $recipe->save();
            $this->syncRelations($recipe, $data, $settings);
            $imageStorage->store($recipe, $request->file('images', []));
        });

        return new RecipeResource($this->recipeQuery()->findOrFail($recipe->getKey()));
    }

    public function destroy(Recipe $recipe, RecipeImageStorage $imageStorage): JsonResponse
    {
        Gate::authorize('delete', $recipe);
        DB::transaction(function () use ($recipe, $imageStorage): void {
            $imageStorage->deleteForRecipe($recipe);
            $recipe->delete();
        });

        return response()->json(['data' => ['deleted' => true]]);
    }

    public function publish(Recipe $recipe): RecipeResource
    {
        Gate::authorize('publish', $recipe);
        abort_if($recipe->images()->count() < 1, 422, 'A recipe must have at least one image before publication.');

        $recipe = DB::transaction(function () use ($recipe): Recipe {
            $recipe->status = Recipe::STATUS_PUBLISHED;
            $recipe->published_at = now();
            $recipe->save();

            return $recipe;
        });

        return new RecipeResource($this->recipeQuery()->findOrFail($recipe->getKey()));
    }

    private function canView(Recipe $recipe): bool
    {
        return $recipe->status === Recipe::STATUS_PUBLISHED
            || (request()->user() !== null && request()->user()->getKey() === $recipe->user_id);
    }

    /**
     * @param  Builder<Recipe>  $query
     * @param  array<string, mixed>  $filters
     */
    private function applyFilters(Builder $query, array $filters): void
    {
        if (filled($filters['search'] ?? null)) {
            $search = mb_strtolower(trim((string) $filters['search']));
            $pattern = '%'.$search.'%';
            $query->where(function (Builder $searchQuery) use ($pattern): void {
                $searchQuery
                    ->whereRaw('LOWER(name) LIKE ?', [$pattern])
                    ->orWhereRaw('LOWER(description) LIKE ?', [$pattern])
                    ->orWhereRaw('LOWER(recommendation) LIKE ?', [$pattern])
                    ->orWhereHas('tags', function (Builder $tagQuery) use ($pattern): void {
                        $tagQuery
                            ->whereRaw('LOWER(tags.name) LIKE ?', [$pattern])
                            ->orWhereRaw('LOWER(tags.slug) LIKE ?', [$pattern]);
                    });
            });
        }

        if (filled($filters['camera_model_id'] ?? null)) {
            $query->where('camera_model_id', $filters['camera_model_id']);
        }

        if (filled($filters['film_simulation'] ?? null)) {
            $query->whereHas('settings', function (Builder $settingQuery) use ($filters): void {
                $settingQuery
                    ->where('setting_key', 'film_simulation')
                    ->whereJsonContains('value', $filters['film_simulation']);
            });
        }

        $this->applyRelationFilter($query, 'categories', $filters['categories'] ?? []);
        $this->applyRelationFilter($query, 'tags', $filters['tags'] ?? []);
    }

    /**
     * @param  Builder<Recipe>  $query
     * @param  array<int, string>  $values
     */
    private function applyRelationFilter(Builder $query, string $relation, array $values): void
    {
        if ($values === []) {
            return;
        }

        $query->whereHas($relation, function (Builder $relationQuery) use ($values, $relation): void {
            $relationQuery->where(function (Builder $valueQuery) use ($values, $relation): void {
                $valueQuery
                    ->whereIn($relation.'.id', $values)
                    ->orWhereIn($relation.'.slug', $values);
            });
        });
    }

    /**
     * @param  array<string, mixed>  $data
     * @param  array<int, array{setting_key: string, value: mixed}>  $settings
     */
    private function syncRelations(Recipe $recipe, array $data, array $settings): void
    {
        if (array_key_exists('categories', $data)) {
            $recipe->categories()->sync($data['categories']);
        }

        if (array_key_exists('tags', $data)) {
            $tagIDs = collect($data['tags'])
                ->map(fn (string $name): Tag => Tag::firstOrCreate(
                    ['slug' => Str::slug($name)],
                    ['name' => $name],
                ))
                ->map(fn (Tag $tag): string => $tag->getKey())
                ->all();
            $recipe->tags()->sync($tagIDs);
        }

        if (array_key_exists('settings', $data) || $settings !== []) {
            $recipe->settings()->delete();
            foreach ($settings as $setting) {
                $capability = CameraCapability::query()
                    ->where('camera_model_id', $recipe->getAttribute('camera_model_id'))
                    ->where('setting_key', $setting['setting_key'])
                    ->firstOrFail();
                RecipeSetting::create([
                    'recipe_id' => $recipe->getKey(),
                    'camera_capability_id' => $capability->getKey(),
                    'setting_key' => $setting['setting_key'],
                    'value' => $setting['value'],
                ]);
            }
        }
    }

    private function recipeQuery()
    {
        return Recipe::query()->with([
            'cameraModel',
            'user',
            'categories',
            'tags',
            'settings',
            'images',
            'provenance',
        ]);
    }
}
