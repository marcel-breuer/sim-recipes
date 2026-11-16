<?php

namespace App\Mcp\Resources;

use App\Mcp\Support\InternalApiClient;
use Laravel\Mcp\Response;
use Laravel\Mcp\ResponseFactory;

class CategoryCatalogueResource extends ApiBackedResource
{
    protected string $name = 'categories';

    protected string $title = 'Recipe categories';

    protected string $description = 'JSON list of the predefined recipe categories (ID, name, slug) used by recipe writes and search filters.';

    protected string $uri = 'simrecipes://categories';

    public function handle(InternalApiClient $api): Response|ResponseFactory
    {
        return $this->fetch($api, '/categories');
    }
}
