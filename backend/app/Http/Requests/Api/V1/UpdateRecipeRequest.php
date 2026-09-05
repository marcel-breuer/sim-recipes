<?php

namespace App\Http\Requests\Api\V1;

class UpdateRecipeRequest extends StoreRecipeRequest
{
    public function rules(): array
    {
        $rules = parent::rules();
        $rules['name'] = ['sometimes', 'required', 'string', 'max:120'];
        $rules['camera_model_id'] = ['sometimes', 'required', 'string', 'exists:camera_models,id'];

        return $rules;
    }
}
