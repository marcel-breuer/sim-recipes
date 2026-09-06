<?php

namespace App\Services\Moderation;

use Illuminate\Validation\ValidationException;

final class UserGeneratedContentSafety
{
    /**
     * This deterministic pre-publication screen is deliberately conservative.
     * Reports and admin review remain the source of truth for images and content
     * that cannot be classified reliably from text alone.
     *
     * @param  array<string, mixed>  $content
     */
    public function assertAllowed(array $content): void
    {
        $text = $this->flatten($content);
        $patterns = config('moderation.blocked_patterns', [
            '\\bporn(?:ography)?\\b',
            '\\bsexual exploitation\\b',
            '\\bchild sexual abuse\\b',
            '\\bkill yourself\\b',
        ]);

        foreach ($patterns as $pattern) {
            if (preg_match('/'.$pattern.'/iu', $text) === 1) {
                throw ValidationException::withMessages([
                    'content' => ['This content cannot be posted because it violates the community standards.'],
                ]);
            }
        }
    }

    /**
     * @param  array<string, mixed>  $content
     */
    private function flatten(array $content): string
    {
        $values = [];
        array_walk_recursive($content, static function (mixed $value) use (&$values): void {
            if (is_string($value)) {
                $values[] = $value;
            }
        });

        return implode(' ', $values);
    }
}
