<?php

namespace App\Mcp\Prompts;

use Laravel\Mcp\Request;
use Laravel\Mcp\Response;
use Laravel\Mcp\Server\Prompt;
use Laravel\Mcp\Server\Prompts\Argument;

class FindRecipePrompt extends Prompt
{
    protected string $name = 'find_community_recipe';

    protected string $title = 'Find a community recipe';

    protected string $description = 'Guides an agent to find the best published recipes for a camera, subject and look, and optionally save one to the user\'s library.';

    /**
     * @return array<int, Argument>
     */
    public function arguments(): array
    {
        return [
            new Argument('request', 'What the user is looking for, in their own words.', true),
            new Argument('camera', 'Camera model name or slug, if known.', false),
        ];
    }

    public function handle(Request $request): Response
    {
        $wish = (string) $request->get('request', '');
        $camera = (string) $request->get('camera', '');
        $cameraHint = $camera !== '' ? "The user shoots with: {$camera}." : 'Ask which camera the user owns if it matters.';

        return Response::text(<<<TEXT
            Find community recipes matching: {$wish}
            {$cameraHint}

            1. Resolve the camera with list_cameras and use its ID as camera_model_id; set compatibility_evidence when the user wants verified settings.
            2. Call search_recipes using subjects, lighting, looks, tags or search text. Try feed "popular" first, then "newest".
            3. Open the two or three best results with get_recipe and compare their settings and example images.
            4. Present the recommendation with the reason. Only call copy_recipe, like_recipe or add_recipe_to_collection if the user asks you to.
            TEXT);
    }
}
