<?php

namespace Tests\Unit;

use App\Services\Auth\AppleIdentityTokenVerifier;
use App\Services\Auth\InvalidAppleIdentityToken;
use Firebase\JWT\JWT;
use Illuminate\Support\Facades\Cache;
use Illuminate\Support\Facades\Http;
use Tests\TestCase;

class AppleIdentityTokenVerifierTest extends TestCase
{
    public function test_it_verifies_an_apple_signed_identity_token(): void
    {
        $this->configureAppleKeySet();
        $token = $this->signedToken(now()->addMinutes(5)->timestamp);

        $identity = (new AppleIdentityTokenVerifier)->verify($token);

        $this->assertSame('apple-subject-1', $identity->subject);
        $this->assertSame('marcel@example.test', $identity->email);
    }

    public function test_it_rejects_an_expired_identity_token(): void
    {
        $this->configureAppleKeySet();
        $token = $this->signedToken(now()->subMinute()->timestamp);

        $this->expectException(InvalidAppleIdentityToken::class);

        (new AppleIdentityTokenVerifier)->verify($token);
    }

    private function configureAppleKeySet(): void
    {
        config(['services.apple.client_id' => 'com.simrecipes.app']);
        Cache::flush();

        $key = openssl_pkey_new([
            'private_key_type' => OPENSSL_KEYTYPE_RSA,
            'private_key_bits' => 2048,
        ]);
        $details = openssl_pkey_get_details($key);

        Http::fake([
            'https://appleid.apple.com/auth/keys' => Http::response([
                'keys' => [[
                    'kty' => 'RSA',
                    'kid' => 'test-key',
                    'use' => 'sig',
                    'alg' => 'RS256',
                    'n' => $this->base64URL($details['rsa']['n']),
                    'e' => $this->base64URL($details['rsa']['e']),
                ]],
            ]),
        ]);

        $this->privateKey = null;
        openssl_pkey_export($key, $this->privateKey);
    }

    private ?string $privateKey = null;

    private function signedToken(int $expiresAt): string
    {
        return JWT::encode([
            'iss' => 'https://appleid.apple.com',
            'aud' => 'com.simrecipes.app',
            'sub' => 'apple-subject-1',
            'email' => 'marcel@example.test',
            'exp' => $expiresAt,
        ], $this->privateKey, 'RS256', 'test-key');
    }

    private function base64URL(string $value): string
    {
        return rtrim(strtr(base64_encode($value), '+/', '-_'), '=');
    }
}
