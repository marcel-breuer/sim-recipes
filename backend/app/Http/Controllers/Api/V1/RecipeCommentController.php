<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\StoreRecipeCommentRequest;
use App\Http\Resources\Api\V1\RecipeCommentResource;
use App\Models\Recipe;
use App\Models\RecipeComment;
use App\Services\Moderation\UserGeneratedContentSafety;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\Gate;

class RecipeCommentController extends Controller
{
    public function index(Recipe $recipe): AnonymousResourceCollection
    {
        abort_unless($this->canViewRecipe($recipe), 404);

        $query = RecipeComment::query()
            ->where('recipe_id', $recipe->getKey())
            ->where('is_hidden', false)
            ->with('user')
            ->oldest();

        if (request()->user() !== null) {
            $query->whereDoesntHave('user.blocksReceived', fn (Builder $blockQuery) => $blockQuery
                ->where('blocker_id', request()->user()->getKey()));
        }

        return RecipeCommentResource::collection($query->paginate(50));
    }

    public function store(
        StoreRecipeCommentRequest $request,
        Recipe $recipe,
        UserGeneratedContentSafety $contentSafety,
    ): RecipeCommentResource {
        abort_unless($this->canViewRecipe($recipe), 404);
        $data = $request->validated();
        $contentSafety->assertAllowed($data);

        $comment = RecipeComment::query()->create([
            'recipe_id' => $recipe->getKey(),
            'user_id' => $request->user()->getKey(),
            'body' => $data['body'],
        ]);

        return new RecipeCommentResource($comment->load('user'));
    }

    public function destroy(RecipeComment $comment): JsonResponse
    {
        Gate::authorize('delete', $comment);
        $comment->delete();

        return response()->json(['data' => ['deleted' => true]]);
    }

    private function canViewRecipe(Recipe $recipe): bool
    {
        if ($recipe->is_hidden || $recipe->status !== Recipe::STATUS_PUBLISHED) {
            return false;
        }

        if ($recipe->user()->where('is_suspended', true)->exists()) {
            return false;
        }

        $user = request()->user();

        return $user === null
            || ! $user->blocksCreated()->where('blocked_user_id', $recipe->user_id)->exists();
    }
}
