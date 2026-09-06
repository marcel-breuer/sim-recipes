<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Models\Recipe;
use App\Models\User;
use App\Services\Recipes\RecipeEngagementService;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Gate;

class RecipeEngagementController extends Controller
{
    public function view(
        Request $request,
        Recipe $recipe,
        RecipeEngagementService $engagementService,
    ): JsonResponse {
        $this->ensurePublished($recipe);
        $viewer = $request->user();
        $anonymousKey = $request->header('X-Anonymous-Key')
            ?? hash('sha256', $request->ip().'|'.$request->userAgent());

        $recorded = $engagementService->recordView($recipe, $viewer, $anonymousKey);

        return response()->json([
            'data' => [
                'recorded' => $recorded,
                'views_count' => $recipe->refresh()->views_count,
            ],
        ]);
    }

    public function like(
        Request $request,
        Recipe $recipe,
        RecipeEngagementService $engagementService,
    ): JsonResponse {
        $this->ensurePublished($recipe);
        $user = $request->user();
        abort_unless($user instanceof User, 401);
        $engagementService->like($user, $recipe);

        return response()->json([
            'data' => [
                'liked' => true,
                'likes_count' => $recipe->refresh()->likes_count,
            ],
        ]);
    }

    public function unlike(
        Request $request,
        Recipe $recipe,
        RecipeEngagementService $engagementService,
    ): JsonResponse {
        $this->ensurePublished($recipe);
        $user = $request->user();
        abort_unless($user instanceof User, 401);
        $engagementService->unlike($user, $recipe);

        return response()->json([
            'data' => [
                'liked' => false,
                'likes_count' => $recipe->refresh()->likes_count,
            ],
        ]);
    }

    private function ensurePublished(Recipe $recipe): void
    {
        abort_unless(
            $recipe->status === Recipe::STATUS_PUBLISHED
                && ! $recipe->is_hidden
                && Gate::allows('view', $recipe),
            404,
        );
    }
}
