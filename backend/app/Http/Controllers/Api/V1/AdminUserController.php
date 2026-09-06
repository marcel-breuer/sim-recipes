<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\IndexAdminUserRequest;
use App\Http\Requests\Api\V1\UpdateUserSuspensionRequest;
use App\Http\Resources\Api\V1\AdminUserResource;
use App\Models\User;
use App\Services\Admin\AdminAuditLogger;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;
use Illuminate\Support\Facades\DB;

class AdminUserController extends Controller
{
    public function index(IndexAdminUserRequest $request): AnonymousResourceCollection
    {
        $data = $request->validated();
        $query = User::query()
            ->with('profile')
            ->withCount(['recipes', 'publishedRecipes'])
            ->orderByDesc('created_at')
            ->orderByDesc('id');

        if (is_string($data['search'] ?? null) && $data['search'] !== '') {
            $search = $data['search'];
            $query->where(static function (Builder $userQuery) use ($search): void {
                $userQuery
                    ->where('name', 'ilike', '%'.$search.'%')
                    ->orWhere('email', 'ilike', '%'.$search.'%');
            });
        }

        match ($data['status'] ?? 'active') {
            'suspended' => $query->where('is_suspended', true),
            'all' => null,
            default => $query->where('is_suspended', false),
        };

        return AdminUserResource::collection($query->paginate($data['per_page'] ?? 25));
    }

    public function show(User $user): AdminUserResource
    {
        return new AdminUserResource($user->load('profile')->loadCount(['recipes', 'publishedRecipes']));
    }

    public function updateSuspension(
        UpdateUserSuspensionRequest $request,
        User $user,
        AdminAuditLogger $auditLogger,
    ): AdminUserResource|JsonResponse {
        $data = $request->validated();
        $isSuspended = (bool) $data['is_suspended'];

        if ($user->is($request->user())) {
            $auditLogger->record(
                $request->user(),
                'user.suspension.update',
                $user,
                $data['reason'] ?? null,
                'rejected',
                ['is_suspended' => $isSuspended],
            );

            return response()->json([
                'error' => [
                    'code' => 'self_suspension_forbidden',
                    'message' => 'An administrator cannot suspend their own account.',
                ],
            ], 422);
        }

        $previousIsSuspended = (bool) $user->is_suspended;
        DB::transaction(function () use ($auditLogger, $data, $isSuspended, $previousIsSuspended, $request, $user): void {
            $user->forceFill([
                'is_suspended' => $isSuspended,
                'suspended_at' => $isSuspended ? now() : null,
                'suspension_reason' => $isSuspended ? $data['reason'] : null,
            ])->save();
            $auditLogger->record(
                $request->user(),
                'user.suspension.update',
                $user,
                $data['reason'] ?? null,
                'succeeded',
                [
                    'previous_is_suspended' => $previousIsSuspended,
                    'is_suspended' => $isSuspended,
                ],
            );
        });

        return new AdminUserResource($user->fresh()->load('profile')->loadCount(['recipes', 'publishedRecipes']));
    }
}
