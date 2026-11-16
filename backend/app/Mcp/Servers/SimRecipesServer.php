<?php

namespace App\Mcp\Servers;

use App\Mcp\Prompts\CreateRecipePrompt;
use App\Mcp\Prompts\FindRecipePrompt;
use App\Mcp\Prompts\ReviewRecipePrompt;
use App\Mcp\Resources\CameraCatalogueResource;
use App\Mcp\Resources\CategoryCatalogueResource;
use App\Mcp\Resources\RecipeDocumentResource;
use App\Mcp\Tools\ToolCatalogue;
use Laravel\Mcp\Server;
use Laravel\Mcp\Server\Attributes\Instructions;
use Laravel\Mcp\Server\Attributes\Name;
use Laravel\Mcp\Server\Attributes\Version;

#[Name('SimRecipes')]
#[Version('1.0.0')]
#[Instructions(<<<'TEXT'
SimRecipes is a community for Fujifilm film-simulation recipes. This server acts strictly as the authenticated user: it can read public recipes and the user's own library, and (with a write-scoped token) manage the user's private recipes, collections, comments, likes and follows.

Guidelines:
- Before creating or editing a recipe, read the camera capabilities (get_camera) and use only the setting keys and values they allow.
- Published recipes are immutable. publish_recipe and the delete_* tools cannot be undone: confirm with the user first.
- Images, reports, blocking and administration are not available through MCP.
- Errors use {"error": {"code", "message", "details"}}; fix validation_failed details and retry, but do not retry forbidden, insufficient_scope or rate_limited calls immediately.
TEXT)]
class SimRecipesServer extends Server
{
    public int $defaultPaginationLength = 50;

    protected array $resources = [
        CameraCatalogueResource::class,
        CategoryCatalogueResource::class,
        RecipeDocumentResource::class,
    ];

    protected array $prompts = [
        CreateRecipePrompt::class,
        FindRecipePrompt::class,
        ReviewRecipePrompt::class,
    ];

    protected function boot(): void
    {
        $this->tools = ToolCatalogue::all();
    }
}
