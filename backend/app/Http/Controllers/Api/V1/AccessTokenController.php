<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\StoreAccessTokenRequest;
use App\Http\Resources\Api\V1\AccessTokenResource;
use Illuminate\Http\JsonResponse;
use Illuminate\Http\Resources\Json\AnonymousResourceCollection;

/**
 * Personal access tokens for scripts and MCP clients. Token management itself
 * is restricted to unrestricted first-party sessions (see `token.scope:full`).
 */
class AccessTokenController extends Controller
{
    public const PERSONAL_TOKEN_PREFIX = 'pat:';

    public function index(): AnonymousResourceCollection
    {
        $tokens = request()->user()->tokens()
            ->where('name', 'like', self::PERSONAL_TOKEN_PREFIX.'%')
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->cursorPaginate(config('api.pagination.default_per_page'));

        return AccessTokenResource::collection($tokens);
    }

    public function store(StoreAccessTokenRequest $request): JsonResponse
    {
        $user = $request->user();
        abort_if(
            $user->tokens()->where('name', 'like', self::PERSONAL_TOKEN_PREFIX.'%')->count()
                >= config('api.personal_tokens.max_active'),
            409,
            'The maximum number of personal access tokens has been reached. Revoke one first.',
        );

        $days = (int) ($request->validated('expires_in_days') ?? config('api.personal_tokens.default_expiration_days'));
        $newToken = $user->createToken(
            name: self::PERSONAL_TOKEN_PREFIX.$request->validated('name'),
            abilities: array_values($request->validated('abilities')),
            expiresAt: now()->addDays($days),
        );

        return (new AccessTokenResource($newToken->accessToken))
            ->withPlainTextToken($newToken->plainTextToken)
            ->response()
            ->setStatusCode(201);
    }

    public function destroy(string $token): JsonResponse
    {
        abort_unless(ctype_digit($token), 404);

        $accessToken = request()->user()->tokens()
            ->where('name', 'like', self::PERSONAL_TOKEN_PREFIX.'%')
            ->whereKey($token)
            ->firstOrFail();
        $accessToken->delete();

        return response()->json(['data' => ['revoked' => true]]);
    }
}
