<?php

namespace App\Http\Controllers\Api\V1;

use App\Http\Controllers\Controller;
use App\Http\Requests\Api\V1\AppleLoginRequest;
use App\Http\Resources\Api\V1\AuthSessionResource;
use App\Models\User;
use App\Services\Auth\AppleIdentityTokenVerifierContract;
use App\Services\Auth\InvalidAppleIdentityToken;
use Illuminate\Auth\AuthenticationException;
use Illuminate\Http\JsonResponse;
use Illuminate\Support\Facades\DB;

class AuthController extends Controller
{
    public function apple(
        AppleLoginRequest $request,
        AppleIdentityTokenVerifierContract $tokenVerifier,
    ): AuthSessionResource {
        try {
            $identity = $tokenVerifier->verify($request->string('identity_token')->toString());
        } catch (InvalidAppleIdentityToken) {
            throw new AuthenticationException('The Apple identity token is invalid.', [], null);
        }

        $session = DB::transaction(function () use ($identity, $request): array {
            $user = User::query()->firstOrNew(['apple_subject' => $identity->subject]);

            if (! $user->exists) {
                $user->name = $request->string('name')->trim()->toString() ?: 'SimRecipes user';
                $user->apple_subject = $identity->subject;
            }

            if ($identity->email !== null) {
                $user->email = $identity->email;
                $user->email_verified_at ??= now();
            }

            $user->save();

            $token = $user->createToken(
                name: 'ios',
                abilities: ['*'],
                expiresAt: now()->addDays(config('api.auth_token_expiration_days')),
            );

            return [
                'plain_text_token' => $token->plainTextToken,
                'access_token' => $token->accessToken,
            ];
        });

        return new AuthSessionResource((object) $session);
    }

    public function logout(): JsonResponse
    {
        request()->user()->currentAccessToken()->delete();

        return response()->json([
            'data' => [
                'logged_out' => true,
            ],
        ]);
    }
}
