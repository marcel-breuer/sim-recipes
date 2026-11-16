<?php

namespace App\Mcp\Resources;

use App\Mcp\Support\InternalApiClient;
use Laravel\Mcp\Request;
use Laravel\Mcp\Response;
use Laravel\Mcp\ResponseFactory;
use Laravel\Mcp\Server\Contracts\HasUriTemplate;
use Laravel\Mcp\Support\UriTemplate;

class RecipeDocumentResource extends ApiBackedResource implements HasUriTemplate
{
    private const SAFE_ID = '/^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$/';

    protected string $name = 'recipe';

    protected string $title = 'Recipe';

    protected string $description = 'A recipe as JSON, addressed by ID: settings, images, tags, categories and provenance. Published recipes and the caller\'s own private recipes are readable.';

    public function uriTemplate(): UriTemplate
    {
        return new UriTemplate('simrecipes://recipes/{recipe}');
    }

    public function handle(Request $request, InternalApiClient $api): Response|ResponseFactory
    {
        $id = (string) $request->get('recipe', '');
        if (preg_match(self::SAFE_ID, $id) !== 1) {
            return Response::error('The recipe ID is not valid.');
        }

        return $this->fetch($api, '/recipes/'.rawurlencode($id));
    }
}
