<?php

namespace App\Services\Recipes;

use App\Models\Recipe;
use App\Models\RecipeProvenance;
use App\Models\RecipeSetting;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Throwable;

final class RecipeCopyService
{
    public function __construct(
        private readonly RecipeImageStorage $imageStorage,
        private readonly RecipeEngagementService $engagementService,
    ) {}

    public function copy(Recipe $source, User $user): Recipe
    {
        return DB::transaction(function () use ($source, $user): Recipe {
            $copy = null;
            try {
                $copy = Recipe::create([
                    'user_id' => $user->getKey(),
                    'camera_model_id' => $source->getAttribute('camera_model_id'),
                    'name' => $source->getAttribute('name'),
                    'description' => $source->getAttribute('description'),
                    'recommendation' => $source->getAttribute('recommendation'),
                    'lens' => $source->getAttribute('lens'),
                ]);
                $copy->categories()->sync($source->categories()->pluck('categories.id')->all());
                $copy->tags()->sync($source->tags()->pluck('tags.id')->all());

                foreach ($source->settings()->get() as $setting) {
                    RecipeSetting::create([
                        'recipe_id' => $copy->getKey(),
                        'camera_capability_id' => $setting->getAttribute('camera_capability_id'),
                        'setting_key' => $setting->getAttribute('setting_key'),
                        'value' => $setting->getAttribute('value'),
                    ]);
                }

                RecipeProvenance::create([
                    'copied_recipe_id' => $copy->getKey(),
                    'source_recipe_id' => $source->getKey(),
                    'source_author_id' => $source->getAttribute('user_id'),
                    'copied_by_user_id' => $user->getKey(),
                ]);

                $this->imageStorage->copyForRecipe($source, $copy);
                $this->engagementService->recordDownload($source, $user, $copy);

                return $copy;
            } catch (Throwable $exception) {
                if ($copy !== null) {
                    $this->imageStorage->deleteForRecipe($copy);
                }

                throw $exception;
            }
        });
    }
}
