<?php

namespace App\Http\Requests\Api\V1;

use App\Support\RecipeExampleContextOptions;
use Illuminate\Contracts\Validation\Validator;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreRecipeRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    protected function prepareForValidation(): void
    {
        foreach (['settings', 'categories', 'tags', 'capture_metadata', 'example_context'] as $field) {
            if (is_string($this->input($field))) {
                $decoded = json_decode($this->input($field), true);
                if (is_array($decoded)) {
                    $this->merge([$field => $decoded]);
                }
            }
        }
    }

    public function withValidator(Validator $validator): void
    {
        $validator->after(function (Validator $validator): void {
            $images = $this->file('images', []);
            foreach (['capture_metadata', 'example_context'] as $field) {
                if (! $this->exists($field)) {
                    continue;
                }

                $metadata = $this->input($field, []);
                if (! is_array($metadata) || count($metadata) !== count($images)) {
                    $validator->errors()->add(
                        $field,
                        ucfirst(str_replace('_', ' ', $field)).' must contain one aligned item for each uploaded image.',
                    );
                }
            }
        });
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
            'capture_metadata' => ['sometimes', 'array', 'max:5'],
            'capture_metadata.*' => ['nullable', 'array:source,camera_make,camera_model,lens_model,exposure,settings,scene_notes,lighting_notes,location,location_shared'],
            'capture_metadata.*.source' => ['required_with:capture_metadata.*', 'string', 'in:fujifilm_jpeg,jpeg_exif'],
            'capture_metadata.*.camera_make' => ['sometimes', 'nullable', 'string', 'max:100'],
            'capture_metadata.*.camera_model' => ['sometimes', 'nullable', 'string', 'max:120'],
            'capture_metadata.*.lens_model' => ['sometimes', 'nullable', 'string', 'max:120'],
            'capture_metadata.*.exposure' => ['sometimes', 'nullable', 'array:iso,exposure_time_seconds,f_number,focal_length_mm,exposure_compensation_ev'],
            'capture_metadata.*.exposure.iso' => ['sometimes', 'nullable', 'numeric', 'min:1', 'max:1000000'],
            'capture_metadata.*.exposure.exposure_time_seconds' => ['sometimes', 'nullable', 'numeric', 'gt:0', 'max:1000000'],
            'capture_metadata.*.exposure.f_number' => ['sometimes', 'nullable', 'numeric', 'gt:0', 'max:1000'],
            'capture_metadata.*.exposure.focal_length_mm' => ['sometimes', 'nullable', 'numeric', 'gt:0', 'max:10000'],
            'capture_metadata.*.exposure.exposure_compensation_ev' => ['sometimes', 'nullable', 'numeric', 'min:-20', 'max:20'],
            'capture_metadata.*.settings' => ['sometimes', 'array', 'max:50'],
            'capture_metadata.*.settings.*' => ['array:setting_key,value,source,was_edited'],
            'capture_metadata.*.settings.*.setting_key' => ['required', 'string', 'max:100'],
            'capture_metadata.*.settings.*.value' => ['present'],
            'capture_metadata.*.settings.*.source' => ['required', 'string', 'max:255'],
            'capture_metadata.*.settings.*.was_edited' => ['required', 'boolean'],
            'capture_metadata.*.scene_notes' => ['sometimes', 'nullable', 'string', 'max:500'],
            'capture_metadata.*.lighting_notes' => ['sometimes', 'nullable', 'string', 'max:500'],
            'capture_metadata.*.location' => ['sometimes', 'nullable', 'array:latitude,longitude'],
            'capture_metadata.*.location.latitude' => ['required_with:capture_metadata.*.location', 'numeric', 'between:-90,90'],
            'capture_metadata.*.location.longitude' => ['required_with:capture_metadata.*.location', 'numeric', 'between:-180,180'],
            'capture_metadata.*.location_shared' => ['required_with:capture_metadata.*', 'boolean'],
            'example_context' => ['sometimes', 'array', 'max:5'],
            'example_context.*' => ['nullable', 'array:subjects,lighting,looks'],
            'example_context.*.subjects' => ['sometimes', 'array', 'max:10'],
            'example_context.*.subjects.*' => ['string', 'distinct', Rule::in(RecipeExampleContextOptions::SUBJECTS)],
            'example_context.*.lighting' => ['sometimes', 'array', 'max:10'],
            'example_context.*.lighting.*' => ['string', 'distinct', Rule::in(RecipeExampleContextOptions::LIGHTING)],
            'example_context.*.looks' => ['sometimes', 'array', 'max:8'],
            'example_context.*.looks.*' => ['string', 'distinct', Rule::in(RecipeExampleContextOptions::LOOKS)],
        ];
    }
}
