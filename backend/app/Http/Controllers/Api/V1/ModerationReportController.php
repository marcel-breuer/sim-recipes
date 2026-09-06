<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\StoreModerationReportRequest;
use App\Http\Requests\Api\V1\UpdateModerationReportRequest;
use App\Http\Resources\Api\V1\ModerationReportResource;
use App\Models\ModerationReport;
use App\Models\Profile;
use App\Models\Recipe;
use App\Models\RecipeComment;
use App\Models\RecipeImage;
use App\Models\User;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;

class ModerationReportController extends Controller
{
    public function storeRecipe(StoreModerationReportRequest $request, Recipe $recipe): ModerationReportResource
    {
        abort_unless($this->isReportableRecipe($recipe), 404);

        return $this->store($request, $recipe);
    }

    public function storeImage(StoreModerationReportRequest $request, RecipeImage $recipeImage): ModerationReportResource
    {
        $recipe = $recipeImage->recipe;
        abort_unless($recipe instanceof Recipe && $this->isReportableRecipe($recipe), 404);

        return $this->store($request, $recipeImage);
    }

    public function storeComment(StoreModerationReportRequest $request, RecipeComment $comment): ModerationReportResource
    {
        abort_unless($this->isReportableComment($comment), 404);

        return $this->store($request, $comment);
    }

    public function storeProfile(StoreModerationReportRequest $request, string $username): ModerationReportResource
    {
        $profile = Profile::query()->where('username', $username)->firstOrFail();
        $user = User::query()->findOrFail($profile->user_id);
        abort_if($user->is_suspended, 404);

        return $this->store($request, $user);
    }

    public function storeUser(StoreModerationReportRequest $request, User $user): ModerationReportResource
    {
        abort_if($user->is_suspended, 404);

        return $this->store($request, $user);
    }

    public function index(Request $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', ModerationReport::class);

        $query = ModerationReport::query()->latest();
        if ($request->filled('status')) {
            $query->where('status', $request->string('status')->toString());
        }

        return ModerationReportResource::collection($query->paginate(50));
    }

    public function update(UpdateModerationReportRequest $request, ModerationReport $report): ModerationReportResource
    {
        Gate::authorize('update', $report);
        $data = $request->validated();

        DB::transaction(function () use ($report, $data, $request): void {
            $resolution = $data['resolution'] ?? 'dismiss';
            $this->applyResolution($report, $resolution);
            $report->forceFill([
                'status' => $data['status'],
                'resolution' => $resolution,
                'reviewed_by' => $request->user()->getKey(),
                'reviewed_at' => now(),
            ])->save();
        });

        return new ModerationReportResource($report->fresh());
    }

    private function store(StoreModerationReportRequest $request, object $reportable): ModerationReportResource
    {
        $report = ModerationReport::query()->firstOrCreate(
            [
                'reporter_id' => $request->user()->getKey(),
                'reportable_type' => $reportable::class,
                'reportable_id' => $reportable->getKey(),
                'status' => ModerationReport::STATUS_OPEN,
            ],
            [
                'reason' => $request->string('reason')->toString(),
                'details' => $request->input('details'),
            ],
        );

        return new ModerationReportResource($report);
    }

    private function isReportableRecipe(Recipe $recipe): bool
    {
        return $recipe->status === Recipe::STATUS_PUBLISHED
            && ! $recipe->is_hidden
            && ! $recipe->user()->where('is_suspended', true)->exists();
    }

    private function applyResolution(ModerationReport $report, string $resolution): void
    {
        $target = $report->reportable;
        if ($target instanceof Recipe) {
            if ($resolution === 'hide_content') {
                $target->forceFill([
                    'is_hidden' => true,
                    'moderated_at' => now(),
                    'moderation_reason' => $report->reason,
                ])->save();
            } elseif ($resolution === 'restore_content') {
                $target->forceFill([
                    'is_hidden' => false,
                    'moderated_at' => null,
                    'moderation_reason' => null,
                ])->save();
            }
        } elseif ($target instanceof RecipeImage && $resolution === 'hide_content') {
            $target->recipe?->forceFill([
                'is_hidden' => true,
                'moderated_at' => now(),
                'moderation_reason' => $report->reason,
            ])->save();
        } elseif ($target instanceof RecipeComment) {
            if ($resolution === 'hide_content') {
                $target->forceFill([
                    'is_hidden' => true,
                    'moderated_at' => now(),
                    'moderation_reason' => $report->reason,
                ])->save();
            } elseif ($resolution === 'restore_content') {
                $target->forceFill([
                    'is_hidden' => false,
                    'moderated_at' => null,
                    'moderation_reason' => null,
                ])->save();
            }
        } elseif ($target instanceof User) {
            if ($resolution === 'suspend_user') {
                $target->forceFill(['is_suspended' => true])->save();
            } elseif ($resolution === 'restore_content') {
                $target->forceFill(['is_suspended' => false])->save();
            }
        }
    }

    private function isReportableComment(RecipeComment $comment): bool
    {
        $recipe = $comment->recipe;

        return $recipe instanceof Recipe
            && $recipe->status === Recipe::STATUS_PUBLISHED
            && ! $recipe->is_hidden
            && ! $comment->is_hidden
            && ! $recipe->user()->where('is_suspended', true)->exists()
            && ! $comment->user()->where('is_suspended', true)->exists();
    }
}
