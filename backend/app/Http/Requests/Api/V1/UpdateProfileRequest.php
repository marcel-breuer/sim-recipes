<?php

namespace App\Http\Requests\Api\V1;

use App\Models\Profile;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateProfileRequest extends FormRequest
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
        $profileID = Profile::query()
            ->where('user_id', $this->user()?->getKey())
            ->value('id');
        $usernameRules = [
            'string',
            'min:3',
            'max:32',
            'regex:/^[a-z0-9_]+$/',
            Rule::unique(Profile::class, 'username')->ignore($profileID),
        ];

        if ($profileID === null) {
            $usernameRules[] = 'required';
        } else {
            $usernameRules[] = 'sometimes';
        }

        return [
            'username' => $usernameRules,
            'camera_model_id' => ['sometimes', 'nullable', 'string', 'exists:camera_models,id'],
            'biography' => ['sometimes', 'nullable', 'string', 'max:1000'],
            'profile_image' => [
                'sometimes',
                'nullable',
                'file',
                'image',
                'mimes:jpg,jpeg,png,webp',
                'max:5120',
            ],
            'remove_profile_image' => ['sometimes', 'boolean'],
        ];
    }
}
