<?php

namespace App\Http\Resources\Api\V1;

use App\Http\Controllers\Api\V1\AccessTokenController;
use Illuminate\Http\Request;
use Illuminate\Http\Resources\Json\JsonResource;
use Illuminate\Support\Str;
use Laravel\Sanctum\PersonalAccessToken;

/**
 * Metadata of a personal access token. The secret is only ever included once,
 * in the response that creates the token (`plain_text_token` on the resource
 * wrapper), and is never stored or logged in clear text.
 *
 * @mixin PersonalAccessToken
 */
class AccessTokenResource extends JsonResource
{
    public ?string $plainTextToken = null;

    public function withPlainTextToken(string $plainTextToken): static
    {
        $this->plainTextToken = $plainTextToken;

        return $this;
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(Request $request): array
    {
        $data = [
            'id' => (string) $this->resource->getKey(),
            'name' => Str::after((string) $this->resource->getAttribute('name'), AccessTokenController::PERSONAL_TOKEN_PREFIX),
            'abilities' => $this->resource->getAttribute('abilities'),
            'last_used_at' => $this->resource->getAttribute('last_used_at')?->toISOString(),
            'expires_at' => $this->resource->getAttribute('expires_at')?->toISOString(),
            'created_at' => $this->resource->getAttribute('created_at')?->toISOString(),
        ];

        if ($this->plainTextToken !== null) {
            $data['token'] = $this->plainTextToken;
        }

        return $data;
    }
}
