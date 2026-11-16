<?php

namespace App\Http\Requests\Api\V1;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreAccessTokenRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'min:1', 'max:80'],
            'abilities' => ['required', 'array', 'min:1', 'max:'.count(config('api.personal_tokens.abilities'))],
            'abilities.*' => ['string', 'distinct', Rule::in(config('api.personal_tokens.abilities'))],
            'expires_in_days' => ['sometimes', 'integer', 'min:1', 'max:'.config('api.personal_tokens.max_expiration_days')],
        ];
    }
}
