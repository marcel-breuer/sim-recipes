<?php

namespace App\Mcp\Resources;

use App\Mcp\Support\InternalApiClient;
use Laravel\Mcp\Response;
use Laravel\Mcp\ResponseFactory;

class CameraCatalogueResource extends ApiBackedResource
{
    protected string $name = 'cameras';

    protected string $title = 'Supported camera models';

    protected string $description = 'JSON list of every supported Fujifilm camera model with its capabilities, allowed values and evidence levels. Read this before building recipe settings.';

    protected string $uri = 'simrecipes://cameras';

    public function handle(InternalApiClient $api): Response|ResponseFactory
    {
        return $this->fetch($api, '/cameras');
    }
}
