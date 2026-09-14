<?php

namespace App\Http\Requests\Api\V1;

use Illuminate\Foundation\Http\FormRequest;

class ReorderRecipeCollectionsRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    public function rules(): array
    {
        return [
            'collection_ids' => ['required', 'array'],
            'collection_ids.*' => ['required', 'string', 'distinct'],
        ];
    }
}
