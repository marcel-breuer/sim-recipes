<?php

namespace App\Mcp\Prompts;

use Laravel\Mcp\Request;
use Laravel\Mcp\Response;
use Laravel\Mcp\Server\Prompt;
use Laravel\Mcp\Server\Prompts\Argument;

class ReviewRecipePrompt extends Prompt
{
    protected string $name = 'review_recipe_before_publishing';

    protected string $title = 'Review a recipe before publishing';

    protected string $description = 'Checklist for reviewing one of the user\'s private recipes for completeness before they decide to publish it.';

    /**
     * @return array<int, Argument>
     */
    public function arguments(): array
    {
        return [new Argument('recipe_id', 'ID of the private recipe to review.', true)];
    }

    public function handle(Request $request): Response
    {
        $id = (string) $request->get('recipe_id', '');

        return Response::text(<<<TEXT
            Review the private recipe {$id} before publication.

            1. Call get_recipe with that ID. Check name, description, recommendation, tags, categories and that settings are complete for the camera.
            2. Verify at least one example image exists (publishing requires it) and that image labels (subjects, lighting, looks) describe the real photo.
            3. Report gaps to the user as a short list. Publishing is irreversible and the recipe becomes immutable, so call publish_recipe only after the user explicitly confirms.
            TEXT);
    }
}
