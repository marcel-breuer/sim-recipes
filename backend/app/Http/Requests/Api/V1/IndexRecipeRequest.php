<?php

namespace App\Http\Requests\Api\V1;

use Illuminate\Foundation\Http\FormRequest;

class IndexRecipeRequest extends FormRequest
{
    public function authorize(): bool
    {
        return true;
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'feed' => ['sometimes', 'string', 'in:popular,newest'],
            'search' => ['sometimes', 'nullable', 'string', 'max:100'],
            'camera_model_id' => ['sometimes', 'nullable', 'string', 'exists:camera_models,id'],
            'film_simulation' => ['sometimes', 'nullable', 'string', 'max:100'],
            'categories' => ['sometimes', 'array', 'max:20'],
            'categories.*' => ['string', 'max:100'],
            'tags' => ['sometimes', 'array', 'max:20'],
            'tags.*' => ['string', 'max:100'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:'.config('api.pagination.max_per_page')],
        ];
    }
}
