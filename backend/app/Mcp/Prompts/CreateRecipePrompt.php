<?php

namespace App\Mcp\Prompts;

use Laravel\Mcp\Request;
use Laravel\Mcp\Response;
use Laravel\Mcp\Server\Prompt;
use Laravel\Mcp\Server\Prompts\Argument;

class CreateRecipePrompt extends Prompt
{
    protected string $name = 'create_recipe_draft';

    protected string $title = 'Create a recipe draft';

    protected string $description = 'Guides an agent through drafting a valid private film-simulation recipe for a camera model from a style description.';

    /**
     * @return array<int, Argument>
     */
    public function arguments(): array
    {
        return [
            new Argument('camera', 'Camera model name or slug, e.g. "X-S20".', true),
            new Argument('style', 'The look the user wants, e.g. "warm, low-contrast street photography".', true),
        ];
    }

    public function handle(Request $request): Response
    {
        $camera = (string) $request->get('camera', '');
        $style = (string) $request->get('style', '');

        return Response::text(<<<TEXT
            Draft a private SimRecipes film-simulation recipe for the camera "{$camera}" with this style: {$style}

            1. Call get_camera (or list_cameras) and read the capabilities. Only use setting_key values and values that the camera allows; note the evidence level of each capability.
            2. Call list_categories and pick fitting category IDs.
            3. Call create_recipe with a short name, a description and recommendation in plain language, relevant tags, and settings that satisfy the capabilities. If the server rejects a value, correct it using the validation details instead of guessing.
            4. Tell the user the recipe is a private draft. Do NOT call publish_recipe: publishing is irreversible and requires at least one example image, so ask the user first.
            TEXT);
    }
}
