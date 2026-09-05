<?php

namespace App\Services\Auth;

use Firebase\JWT\JWK;
use Firebase\JWT\JWT;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Throwable;

final class AppleIdentityTokenVerifier implements AppleIdentityTokenVerifierContract
{
    private const ISSUER = 'https://appleid.apple.com';

    private const KEY_SET_URL = 'https://appleid.apple.com/auth/keys';

    public function verify(string $identityToken): AppleIdentity
    {
        try {
            $claims = (array) JWT::decode(
                $identityToken,
                JWK::parseKeySet($this->appleKeySet()),
            );
        } catch (Throwable $exception) {
            throw new InvalidAppleIdentityToken(previous: $exception);
        }

        $issuer = $claims['iss'] ?? null;
        $audience = $claims['aud'] ?? null;
        $subject = $claims['sub'] ?? null;
        $expiresAt = $claims['exp'] ?? null;
        $clientID = (string) config('services.apple.client_id');

        $audiences = is_array($audience) ? $audience : [$audience];
        if (
            $issuer !== self::ISSUER
            || ! in_array($clientID, $audiences, true)
            || ! is_string($subject)
            || $subject === ''
            || ! is_int($expiresAt)
            || $expiresAt <= now()->timestamp
        ) {
            throw new InvalidAppleIdentityToken;
        }

        $email = $claims['email'] ?? null;

        return new AppleIdentity(
            subject: $subject,
            email: is_string($email) && $email !== '' ? $email : null,
        );
    }

    /**
     * @return array<string, mixed>
     */
    private function appleKeySet(): array
    {
        $keySet = Cache::remember(
            'apple.identity-token.key-set',
            now()->addHours(6),
            fn (): array => Http::acceptJson()
                ->timeout(5)
                ->get(self::KEY_SET_URL)
                ->throw()
                ->json(),
        );

        if (! isset($keySet['keys']) || ! is_array($keySet['keys'])) {
            throw new InvalidAppleIdentityToken;
        }

        return $keySet;
    }
}
