<?php

namespace App\Http\Requests\Api\V1;

use App\Models\ModerationReport;
use Illuminate\Foundation\Http\FormRequest;
use Illuminate\Validation\Rule;

class IndexModerationReportRequest extends FormRequest
{
    public function authorize(): bool
    {
        return $this->user()?->is_admin === true;
    }

    public function rules(): array
    {
        return [
            'status' => ['sometimes', 'string', Rule::in([
                ModerationReport::STATUS_OPEN,
                ModerationReport::STATUS_IN_REVIEW,
                ModerationReport::STATUS_RESOLVED,
                ModerationReport::STATUS_REJECTED,
            ])],
            'reason' => ['sometimes', 'string', Rule::in([
                'objectionable_content',
                'harassment',
                'copyright',
                'spam',
                'other',
            ])],
            'reportable_type' => ['sometimes', 'string', Rule::in([
                'Recipe',
                'RecipeComment',
                'RecipeImage',
                'User',
            ])],
            'from' => ['sometimes', 'date'],
            'to' => ['sometimes', 'date', 'after_or_equal:from'],
            'per_page' => ['sometimes', 'integer', 'min:1', 'max:50'],
        ];
    }
}
