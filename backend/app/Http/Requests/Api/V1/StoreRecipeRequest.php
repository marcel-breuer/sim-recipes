<?php

namespace App\Http\Requests\Api\V1;

use Illuminate\Foundation\Http\FormRequest;

class StoreRecipeRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    protected function prepareForValidation(): void
    {
        foreach (['settings', 'categories', 'tags'] as $field) {
            if (is_string($this->input($field))) {
                $decoded = json_decode($this->input($field), true);
                if (is_array($decoded)) {
                    $this->merge([$field => $decoded]);
                }
            }
        }
    }

    /**
     * @return array<string, array<int, mixed>>
     */
    public function rules(): array
    {
        return [
            'name' => ['required', 'string', 'max:120'],
            'description' => ['sometimes', 'nullable', 'string', 'max:5000'],
            'recommendation' => ['sometimes', 'nullable', 'string', 'max:2000'],
            'lens' => ['sometimes', 'nullable', 'string', 'max:120'],
            'camera_model_id' => ['required', 'string', 'exists:camera_models,id'],
            'categories' => ['sometimes', 'array', 'max:10'],
            'categories.*' => ['string', 'exists:categories,id'],
            'tags' => ['sometimes', 'array', 'max:20'],
            'tags.*' => ['string', 'min:1', 'max:40'],
            'settings' => ['sometimes', 'array', 'max:50'],
            'settings.*.setting_key' => ['required', 'string', 'max:100'],
            'settings.*.value' => ['present'],
            'images' => ['sometimes', 'array', 'max:5'],
            'images.*' => ['file', 'image', 'mimes:jpg,jpeg,png,webp', 'max:25600'],
        ];
    }
}
