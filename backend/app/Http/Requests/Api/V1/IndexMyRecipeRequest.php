<?php

namespace App\Http\Requests\Api\V1;

use Illuminate\Foundation\Http\FormRequest;

class IndexMyRecipeRequest extends FormRequest
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
            'status' => ['sometimes', 'string', 'in:private,published'],
            'search' => ['sometimes', 'nullable', 'string', 'max:100'],
            'camera_model_id' => ['sometimes', 'nullable', 'string', 'exists:camera_models,id'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:'.config('api.pagination.max_per_page')],
            'cursor' => ['sometimes', 'nullable', 'string', 'max:500'],
        ];
    }
}
