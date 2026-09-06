<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\IndexAdminUserRequest;
use App\Http\Requests\Api\V1\UpdateUserSuspensionRequest;
use App\Http\Resources\Api\V1\AdminUserResource;
use App\Models\User;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

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

    public function updateSuspension(UpdateUserSuspensionRequest $request, User $user): AdminUserResource|JsonResponse
    {
        if ($user->is($request->user())) {
            return response()->json([
                'error' => [
                    'code' => 'self_suspension_forbidden',
                    'message' => 'An administrator cannot suspend their own account.',
                ],
            ], 422);
        }

        $data = $request->validated();
        $isSuspended = (bool) $data['is_suspended'];
        $user->forceFill([
            'is_suspended' => $isSuspended,
            'suspended_at' => $isSuspended ? now() : null,
            'suspension_reason' => $isSuspended ? $data['reason'] : null,
        ])->save();

        return new AdminUserResource($user->fresh()->load('profile')->loadCount(['recipes', 'publishedRecipes']));
    }
}
