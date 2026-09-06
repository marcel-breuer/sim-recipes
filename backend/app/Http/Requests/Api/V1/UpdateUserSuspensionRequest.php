<?php

namespace App\Http\Requests\Api\V1;

use Illuminate\Foundation\Http\FormRequest;

class UpdateUserSuspensionRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->is_admin === true;
    }

    public function rules(): array
    {
        return [
            'is_suspended' => ['required', 'boolean'],
            'reason' => ['required_if:is_suspended,true', 'nullable', 'string', 'max:500'],
        ];
    }
}
