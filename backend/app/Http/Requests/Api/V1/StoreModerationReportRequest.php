<?php

namespace App\Http\Requests\Api\V1;

use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class StoreModerationReportRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user() !== null;
    }

    public function rules(): array
    {
        return [
            'reason' => ['required', 'string', Rule::in(['objectionable_content', 'harassment', 'copyright', 'spam', 'other'])],
            'details' => ['sometimes', 'nullable', 'string', 'max:2000'],
        ];
    }
}
