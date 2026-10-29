<?php

namespace App\Http\Requests\Api\V1;

use App\Support\RecipeExampleContextOptions;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

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
            'compatibility_evidence' => ['sometimes', 'nullable', 'string', 'in:manufacturer_documented,camera_verified'],
            'camera_model_id' => ['nullable', 'string', 'exists:camera_models,id', 'required_with:compatibility_evidence'],
            'film_simulation' => ['sometimes', 'nullable', 'string', 'max:100'],
            'categories' => ['sometimes', 'array', 'max:20'],
            'categories.*' => ['string', 'max:100'],
            'tags' => ['sometimes', 'array', 'max:20'],
            'tags.*' => ['string', 'max:100'],
            'subjects' => ['sometimes', 'array', 'max:10'],
            'subjects.*' => ['string', 'distinct', Rule::in(RecipeExampleContextOptions::SUBJECTS)],
            'lighting' => ['sometimes', 'array', 'max:10'],
            'lighting.*' => ['string', 'distinct', Rule::in(RecipeExampleContextOptions::LIGHTING)],
            'looks' => ['sometimes', 'array', 'max:8'],
            'looks.*' => ['string', 'distinct', Rule::in(RecipeExampleContextOptions::LOOKS)],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:'.config('api.pagination.max_per_page')],
        ];
    }
}
