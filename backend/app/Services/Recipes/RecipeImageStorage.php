<?php

namespace App\Services\Recipes;

use App\Jobs\GenerateRecipeImageDerivatives;
use App\Models\Recipe;
use App\Models\RecipeImage;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Illuminate\Validation\ValidationException;
use Throwable;

class RecipeImageStorage
{
    /**
     * @param  array<int, UploadedFile>  $images
     */
    public function store(Recipe $recipe, array $images): void
    {
        if ($images === []) {
            return;
        }

        $userID = $recipe->getAttribute('user_id');
        User::query()->whereKey($userID)->lockForUpdate()->firstOrFail();

        $maxPerRecipe = (int) config('recipes.images.max_per_recipe', 5);
        $existingCount = RecipeImage::query()->where('recipe_id', $recipe->getKey())->count();
        if ($existingCount + count($images) > $maxPerRecipe) {
            throw ValidationException::withMessages([
                'images' => ['A recipe may contain at most '.$maxPerRecipe.' images.'],
            ]);
        }

        $sizes = array_map(fn (UploadedFile $image): int => $this->sizeOf($image), $images);
        $maxOriginalBytes = (int) config('recipes.images.max_original_bytes', 25 * 1024 * 1024);
        foreach ($sizes as $size) {
            if ($size > $maxOriginalBytes) {
                throw ValidationException::withMessages([
                    'images' => ['Each original image must be no larger than 25 MB.'],
                ]);
            }
        }

        $usedBytes = (int) RecipeImage::query()
            ->join('recipes', 'recipes.id', '=', 'recipe_images.recipe_id')
            ->where('recipes.user_id', $userID)
            ->sum('recipe_images.original_size_bytes');
        $quotaBytes = (int) config('recipes.images.user_quota_bytes', 5 * 1024 * 1024 * 1024);
        if ($usedBytes + array_sum($sizes) > $quotaBytes) {
            throw ValidationException::withMessages([
                'images' => ['The user image storage quota has been exceeded.'],
            ]);
        }

        $diskName = config('filesystems.default');
        if (! is_string($diskName)) {
            throw new \RuntimeException('The default filesystem disk is not configured.');
        }

        $maxSortOrder = RecipeImage::query()
            ->where('recipe_id', $recipe->getKey())
            ->max('sort_order');
        $sortOrder = $maxSortOrder === null ? 0 : (int) $maxSortOrder + 1;
        if ($sortOrder + count($images) > $maxPerRecipe) {
            throw ValidationException::withMessages([
                'images' => ['A recipe may contain at most '.$maxPerRecipe.' images.'],
            ]);
        }
        $storedPaths = [];

        try {
            foreach ($images as $index => $image) {
                $path = $image->store('recipes/'.$recipe->getKey(), $diskName);
                $storedPaths[] = $path;
                $imageRecord = RecipeImage::create([
                    'recipe_id' => $recipe->getKey(),
                    'storage_disk' => $diskName,
                    'original_path' => $path,
                    'original_size_bytes' => $sizes[$index],
                    'mime_type' => $image->getMimeType(),
                    'sort_order' => $sortOrder + $index,
                ]);
                GenerateRecipeImageDerivatives::dispatch($imageRecord->getKey())->afterCommit();
            }
        } catch (Throwable $exception) {
            Storage::disk($diskName)->delete($storedPaths);
            throw $exception;
        }
    }

    public function deleteForRecipe(Recipe $recipe): void
    {
        $images = RecipeImage::query()->where('recipe_id', $recipe->getKey())->get();
        foreach ($images as $image) {
            $this->delete($image);
        }
    }

    public function delete(RecipeImage $image): void
    {
        $diskName = $image->getAttribute('storage_disk');
        if (is_string($diskName)) {
            $paths = [$image->getAttribute('original_path')];
            $derivatives = $image->getAttribute('derivatives');
            if (is_array($derivatives)) {
                $paths = array_merge($paths, array_values(array_filter($derivatives, 'is_string')));
            }
            Storage::disk($diskName)->delete(array_values(array_filter($paths, 'is_string')));
        }

        $image->delete();
    }

    private function sizeOf(UploadedFile $image): int
    {
        $size = $image->getSize();
        if (! is_int($size) || $size < 1) {
            throw ValidationException::withMessages([
                'images' => ['Each image must contain data.'],
            ]);
        }

        return $size;
    }
}
