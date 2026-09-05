<?php

namespace App\Http\Resources\Api\V1;

use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * @property-read string $plain_text_token
 * @property-read PersonalAccessToken $access_token
 */
class AuthSessionResource extends JsonResource
{
    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        return [
            'token' => $this->plain_text_token,
            'expires_at' => $this->access_token->expires_at?->toISOString(),
            'user' => [
                'id' => $this->access_token->tokenable->getKey(),
                'name' => $this->access_token->tokenable->name,
                'email' => $this->access_token->tokenable->email,
            ],
        ];
    }
}
