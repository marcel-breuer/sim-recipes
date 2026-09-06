<?php

namespace App\Http\Requests\Api\V1;

use App\Models\ModerationReport;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class UpdateModerationReportRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->is_admin === true;
    }

    public function rules(): array
    {
        return [
            'status' => ['required', 'string', Rule::in([
                ModerationReport::STATUS_IN_REVIEW,
                ModerationReport::STATUS_RESOLVED,
                ModerationReport::STATUS_REJECTED,
            ])],
            'resolution' => ['sometimes', 'nullable', 'string', Rule::in([
                'hide_content',
                'suspend_user',
                'restore_content',
                'dismiss',
            ])],
        ];
    }
}
