<?php

namespace App\Jobs;

use App\Models\RecipeImage;
use Illuminate\Bus\Queueable;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Bus\Dispatchable;
use Illuminate\Queue\InteractsWithQueue;
use Illuminate\Queue\SerializesModels;
use Illuminate\Support\Facades\Image;
use Illuminate\Support\Facades\Storage;
use Throwable;

class GenerateRecipeImageDerivatives implements ShouldQueue
{
    use Dispatchable, InteractsWithQueue, Queueable, SerializesModels;

    public function __construct(public string $recipeImageID) {}

    public function handle(): void
    {
        $imageRecord = RecipeImage::query()->find($this->recipeImageID);
        if ($imageRecord === null) {
            return;
        }

        $diskName = $imageRecord->getAttribute('storage_disk');
        $originalPath = $imageRecord->getAttribute('original_path');
        if (! is_string($diskName) || ! is_string($originalPath)) {
            $imageRecord->update(['processing_status' => 'failed']);

            return;
        }

        try {
            $disk = Storage::disk($diskName);
            $original = Image::fromStorage($originalPath, $diskName)->orient();
            [$width, $height] = $original->dimensions();
            $derivativePaths = [];

            foreach (config('recipes.images.derivatives', []) as $name => $maxWidth) {
                if (! is_string($name) || ! is_int($maxWidth)) {
                    continue;
                }

                $derivative = Image::fromStorage($originalPath, $diskName)->orient();
                if ($derivative->width() > $maxWidth) {
                    $derivative->scale($maxWidth);
                }

                $derivativePath = 'recipes/'.$imageRecord->getAttribute('recipe_id').'/derivatives/'.$imageRecord->getKey().'/'.$name.'.webp';
                $disk->put($derivativePath, $derivative->toWebp()->quality(82)->toBytes());
                $derivativePaths[$name] = $derivativePath;
            }

            $imageRecord->update([
                'width' => $width,
                'height' => $height,
                'derivatives' => $derivativePaths,
                'processing_status' => 'ready',
            ]);
        } catch (Throwable $exception) {
            $imageRecord->update(['processing_status' => 'failed']);
            throw $exception;
        }
    }
}
