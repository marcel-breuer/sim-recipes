<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\IndexModerationReportRequest;
use App\Http\Requests\Api\V1\StoreModerationReportRequest;
use App\Http\Requests\Api\V1\UpdateModerationReportRequest;
use App\Http\Resources\Api\V1\ModerationReportResource;
use App\Models\ModerationReport;
use App\Models\Profile;
use App\Models\Recipe;
use App\Models\RecipeComment;
use App\Models\RecipeImage;
use App\Models\User;
use App\Services\Admin\AdminAuditLogger;
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

    public function index(IndexModerationReportRequest $request): AnonymousResourceCollection
    {
        Gate::authorize('viewAny', ModerationReport::class);

        $filters = $request->validated();
        $query = ModerationReport::query()
            ->with(['reporter', 'reportable'])
            ->orderByRaw("case when status in ('open', 'in_review') then 0 else 1 end")
            ->latest();
        if (isset($filters['status'])) {
            $query->where('status', $filters['status']);
        }
        if (isset($filters['reason'])) {
            $query->where('reason', $filters['reason']);
        }
        if (isset($filters['reportable_type'])) {
            $reportableType = match ($filters['reportable_type']) {
                'Recipe' => Recipe::class,
                'RecipeComment' => RecipeComment::class,
                'RecipeImage' => RecipeImage::class,
                'User' => User::class,
            };
            $query->where('reportable_type', $reportableType);
        }
        if (isset($filters['from'])) {
            $query->whereDate('created_at', '>=', $filters['from']);
        }
        if (isset($filters['to'])) {
            $query->whereDate('created_at', '<=', $filters['to']);
        }

        $reports = $query->paginate($filters['per_page'] ?? 25);
        $reports->getCollection()->loadMorph('reportable', [
            Recipe::class => ['user'],
            RecipeComment::class => ['user'],
            RecipeImage::class => ['recipe'],
        ]);

        return ModerationReportResource::collection($reports);
    }

    public function update(
        UpdateModerationReportRequest $request,
        ModerationReport $report,
        AdminAuditLogger $auditLogger,
    ): ModerationReportResource {
        Gate::authorize('update', $report);
        $data = $request->validated();

        $outcome = 'succeeded';
        DB::transaction(function () use ($auditLogger, $report, $data, $request, &$outcome): void {
            $report->refresh();
            $previousStatus = $report->status;
            if (in_array($report->status, [ModerationReport::STATUS_RESOLVED, ModerationReport::STATUS_REJECTED], true)) {
                $outcome = 'noop';
                $auditLogger->record(
                    $request->user(),
                    'moderation.report.resolve',
                    $report,
                    $data['reviewer_note'] ?? $report->reason,
                    $outcome,
                    [
                        'previous_status' => $previousStatus,
                        'status' => $report->status,
                        'resolution' => $report->resolution,
                    ],
                );

                return;
            }

            $resolution = $data['resolution'] ?? 'dismiss';
            $this->applyResolution($report, $resolution);
            $report->forceFill([
                'status' => $data['status'],
                'resolution' => $resolution,
                'reviewer_note' => $data['reviewer_note'] ?? null,
                'reviewed_by' => $request->user()->getKey(),
                'reviewed_at' => now(),
            ])->save();
            $auditLogger->record(
                $request->user(),
                'moderation.report.resolve',
                $report,
                $data['reviewer_note'] ?? $report->reason,
                $outcome,
                [
                    'previous_status' => $previousStatus,
                    'status' => $data['status'],
                    'resolution' => $resolution,
                ],
            );
        });

        return new ModerationReportResource($report->fresh()->load(['reporter', 'reportable']));
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
                $target->forceFill([
                    'is_suspended' => true,
                    'suspended_at' => now(),
                    'suspension_reason' => $report->reason,
                ])->save();
            } elseif ($resolution === 'restore_content') {
                $target->forceFill([
                    'is_suspended' => false,
                    'suspended_at' => null,
                    'suspension_reason' => null,
                ])->save();
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
