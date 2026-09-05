<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\RecipeImage;
use App\Services\Recipes\RecipeImageStorage;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Storage;
use Symfony\Component\HttpFoundation\StreamedResponse;

class RecipeImageController extends Controller
{
    public function show(Request $request, RecipeImage $recipeImage): StreamedResponse
    {
        Gate::authorize('view', $recipeImage);

        $variant = $request->query('variant');
        $path = $this->pathForVariant($recipeImage, is_string($variant) ? $variant : null);
        $diskName = $recipeImage->getAttribute('storage_disk');
        abort_unless(is_string($diskName), 404);
        abort_unless(Storage::disk($diskName)->exists($path), 404);

        return Storage::disk($diskName)->response(
            $path,
            basename($path),
            ['Cache-Control' => 'private, max-age=300'],
        );
    }

    public function destroy(RecipeImage $recipeImage, RecipeImageStorage $imageStorage): JsonResponse
    {
        Gate::authorize('delete', $recipeImage);
        DB::transaction(function () use ($imageStorage, $recipeImage): void {
            $imageStorage->delete($recipeImage);
        });

        return response()->json(['data' => ['deleted' => true]]);
    }

    private function pathForVariant(RecipeImage $recipeImage, ?string $variant): string
    {
        if ($variant === null) {
            return (string) $recipeImage->getAttribute('original_path');
        }

        abort_unless(in_array($variant, ['thumbnail', 'detail'], true), 404);

        $derivatives = $recipeImage->getAttribute('derivatives');
        abort_unless(is_array($derivatives) && is_string($derivatives[$variant] ?? null), 404);

        return $derivatives[$variant];
    }
}
