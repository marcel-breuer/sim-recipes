<?php

namespace App\Mcp\Tools;

use App\Support\RecipeExampleContextOptions;

/**
 * The complete MCP tool catalogue. Each entry maps one tool to one REST
 * endpoint; see docs/MCP.md for the documented catalogue and permission model.
 * Admin, moderation-report, block, token-management and image-upload
 * operations are deliberately not exposed through MCP.
 */
final class ToolCatalogue
{
    private const PAGE_SIZE = 'Items per page (1-100, default 20).';

    /**
     * @return array<int, ApiTool>
     */
    public static function all(): array
    {
        return [
            ...self::readTools(),
            ...self::recipeWriteTools(),
            ...self::collectionTools(),
            ...self::socialTools(),
        ];
    }

    /**
     * @return array<int, ApiTool>
     */
    private static function readTools(): array
    {
        return [
            self::read('list_cameras', 'List camera models',
                'List all supported Fujifilm camera models with their capabilities (setting keys, allowed values, evidence level). Call this or get_camera before creating or editing a recipe so that every setting you send is valid for the chosen camera. Public data.',
                '/cameras', []),
            self::read('get_camera', 'Get a camera model',
                'Get one camera model including all of its capabilities: setting keys, value types, allowed values or ranges, and compatibility evidence. Use the returned setting_key and allowed values when building recipe settings.',
                '/cameras/{camera}', [
                    self::path('camera', 'Camera model ID (ULID) or slug, e.g. "fujifilm-x-s20".'),
                ]),
            self::read('list_categories', 'List recipe categories',
                'List the predefined recipe categories. Category IDs from this list are used when creating or updating recipes and as search filters.',
                '/categories', []),
            self::read('search_recipes', 'Search community recipes',
                'Search the public community feed. Only published recipes are returned, never private ones. Combine filters freely; filters of different kinds are ANDed. Results are paginated: pass page to get further results and check meta.last_page. To list the caller\'s own recipes use list_my_recipes instead.',
                '/recipes', [
                    self::query('feed', 'Ordering: "popular" (default, likes x3 + downloads x5 + views) or "newest".', 'string', ['enum' => ['popular', 'newest']]),
                    self::query('search', 'Free text matched against name, description, recommendation and tags (max 100 characters).'),
                    self::query('camera_model_id', 'Only recipes for this camera model ID (ULID from list_cameras).'),
                    self::query('film_simulation', 'Only recipes whose film_simulation setting equals this value, e.g. "Classic Chrome".'),
                    self::query('compatibility_evidence', 'Only recipes whose every setting has at least this evidence level. Requires camera_model_id.', 'string', ['enum' => ['manufacturer_documented', 'camera_verified']]),
                    self::query('categories', 'Category IDs or slugs; any match.', 'string_list'),
                    self::query('tags', 'Tag IDs or slugs; any match.', 'string_list'),
                    self::query('subjects', 'Example-photo subject labels; any match. Allowed: '.implode(', ', RecipeExampleContextOptions::SUBJECTS).'.', 'string_list'),
                    self::query('lighting', 'Example-photo lighting labels; any match. Allowed: '.implode(', ', RecipeExampleContextOptions::LIGHTING).'.', 'string_list'),
                    self::query('looks', 'Example-photo look labels; any match. Allowed: '.implode(', ', RecipeExampleContextOptions::LOOKS).'.', 'string_list'),
                    self::query('per_page', self::PAGE_SIZE, 'integer', ['min' => 1, 'max' => 100]),
                    self::query('page', 'Page number, starting at 1.', 'integer', ['min' => 1]),
                ]),
            self::read('get_recipe', 'Get a recipe',
                'Get one recipe with settings, images, tags, categories and provenance. Works for published recipes and for the caller\'s own private recipes; other users\' private recipes return not_found.',
                '/recipes/{recipe}', [self::path('recipe', 'Recipe ID (ULID).')]),
            self::read('find_similar_recipes', 'Find similar recipes',
                'Return up to 6 published recipes for the same camera model that are most similar to the given recipe by shared categories, tags and identical settings.',
                '/recipes/{recipe}/similar', [self::path('recipe', 'Recipe ID (ULID).')]),
            self::read('list_recipe_comments', 'List recipe comments',
                'List visible comments on a published recipe, paginated. Hidden, deleted and blocked-user comments are omitted by the server.',
                '/recipes/{recipe}/comments', [
                    self::path('recipe', 'Recipe ID (ULID).'),
                    self::query('page', 'Page number, starting at 1.', 'integer', ['min' => 1]),
                ]),
            self::read('get_profile', 'Get a public profile',
                'Get a public user profile by username: biography, camera, follower counts, published recipes and public collections.',
                '/profiles/{username}', [self::path('username', 'The profile username.')]),
            self::read('get_my_profile', 'Get my profile',
                'Get the profile of the signed-in account, including details only the owner can see.',
                '/me/profile', []),
            self::read('list_my_recipes', 'List my recipes',
                'List the caller\'s personal recipe library: private drafts, published recipes and copies of community recipes, newest first. Uses cursor pagination: pass the cursor from meta.next_cursor to continue.',
                '/me/recipes', [
                    self::query('status', 'Only "private" drafts or only "published" recipes.', 'string', ['enum' => ['private', 'published']]),
                    self::query('search', 'Free text over name, description and recommendation.'),
                    self::query('camera_model_id', 'Only recipes for this camera model ID.'),
                    self::query('per_page', self::PAGE_SIZE, 'integer', ['min' => 1, 'max' => 100]),
                    self::query('cursor', 'Opaque cursor from meta.next_cursor of the previous page.'),
                ]),
            self::read('list_my_collections', 'List my collections',
                'List all personal collections of the caller in display order, each with its recipes.',
                '/collections', []),
            self::read('get_collection', 'Get a collection',
                'Get one of the caller\'s collections with its recipes. Collections of other users return forbidden.',
                '/collections/{collection}', [self::path('collection', 'Collection ID (ULID).')]),
        ];
    }

    /**
     * @return array<int, ApiTool>
     */
    private static function recipeWriteTools(): array
    {
        $recipeFields = [
            self::body('name', 'Recipe name (max 120 characters).'),
            self::body('description', 'Description (max 5000 characters).'),
            self::body('recommendation', 'Style recommendation, e.g. "ideal for street photography" (max 2000 characters).'),
            self::body('lens', 'Lens note (max 120 characters).'),
            self::body('categories', 'Category IDs from list_categories (max 10).', 'id_list'),
            self::body('tags', 'Free-form tags (max 20, 40 characters each).', 'string_list'),
            self::body('settings', 'Recipe settings; each setting_key and value must be allowed for the camera model (see get_camera). Sending settings replaces all existing settings.', 'settings'),
        ];

        return [
            self::write('create_recipe', 'Create a private recipe',
                'Create a new PRIVATE recipe in the caller\'s library. It is not visible to others until publish_recipe is called. Images cannot be attached through MCP; add them through the REST API or the app before publishing. Settings are validated against the camera model\'s capabilities and invalid values are rejected with details.',
                'POST', '/recipes', [
                    self::body('name', 'Recipe name (max 120 characters).', 'string', ['required' => true]),
                    self::body('camera_model_id', 'Camera model ID (ULID from list_cameras).', 'string', ['required' => true]),
                    ...array_slice($recipeFields, 1),
                ]),
            self::write('update_recipe', 'Update a private recipe',
                'Update fields of one of the caller\'s PRIVATE recipes. Published recipes are immutable and cannot be changed; use copy_recipe to create an editable copy instead. Only the fields you send change; changing camera_model_id revalidates all settings against the new camera.',
                'PATCH', '/recipes/{recipe}', [
                    self::path('recipe', 'Recipe ID (ULID).'),
                    self::body('camera_model_id', 'New camera model ID; existing settings must be valid for it.'),
                    ...$recipeFields,
                ], idempotent: true),
            self::write('delete_recipe', 'Delete a private recipe',
                'Permanently delete one of the caller\'s PRIVATE recipes including its images. This cannot be undone. Published recipes cannot be deleted.',
                'DELETE', '/recipes/{recipe}', [self::path('recipe', 'Recipe ID (ULID).')], destructive: true, idempotent: true),
            self::write('publish_recipe', 'Publish a recipe',
                'Publish a private recipe to the community. IRREVERSIBLE: a published recipe becomes immutable and cannot be edited or deleted afterwards. The recipe needs at least one image and passes a text safety screen. Confirm with the user before calling.',
                'POST', '/recipes/{recipe}/publish', [self::path('recipe', 'Recipe ID (ULID).')], destructive: true),
            self::write('copy_recipe', 'Copy a community recipe',
                'Copy a published recipe into the caller\'s library as a new private recipe with provenance. Use this to save a community recipe or to get an editable version of a published one. Each call creates another copy.',
                'POST', '/recipes/{recipe}/copy', [self::path('recipe', 'ID of the published recipe to copy.')]),
            self::write('like_recipe', 'Like a recipe',
                'Like a published recipe. Idempotent: liking twice has no further effect.',
                'POST', '/recipes/{recipe}/like', [self::path('recipe', 'Recipe ID (ULID).')], idempotent: true),
            self::write('unlike_recipe', 'Remove a like',
                'Remove the caller\'s like from a recipe. Idempotent: removing a missing like has no effect.',
                'DELETE', '/recipes/{recipe}/like', [self::path('recipe', 'Recipe ID (ULID).')], idempotent: true),
            self::write('add_recipe_comment', 'Comment on a recipe',
                'Post a comment as the caller on a published recipe. The text is publicly visible and passes the same safety screen as recipe text. Only post text the user asked for.',
                'POST', '/recipes/{recipe}/comments', [
                    self::path('recipe', 'Recipe ID (ULID).'),
                    self::body('body', 'Comment text (max 2000 characters).', 'string', ['required' => true]),
                ]),
            self::write('delete_comment', 'Delete my comment',
                'Delete one of the caller\'s own comments. Comments of other users cannot be deleted (forbidden).',
                'DELETE', '/comments/{comment}', [self::path('comment', 'Comment ID (ULID).')], destructive: true, idempotent: true),
        ];
    }

    /**
     * @return array<int, ApiTool>
     */
    private static function collectionTools(): array
    {
        return [
            self::write('create_collection', 'Create a collection',
                'Create a personal collection to organise recipes. Collections are private unless is_public is true; public collections appear on the caller\'s public profile (private recipes in them never do).',
                'POST', '/collections', [
                    self::body('name', 'Collection name (max 80 characters).', 'string', ['required' => true]),
                    self::body('is_public', 'Show on the public profile. Default false.', 'boolean'),
                ]),
            self::write('update_collection', 'Update a collection',
                'Rename a collection, change its visibility or its sort position.',
                'PATCH', '/collections/{collection}', [
                    self::path('collection', 'Collection ID (ULID).'),
                    self::body('name', 'New name (max 80 characters).'),
                    self::body('is_public', 'New visibility.', 'boolean'),
                    self::body('sort_order', 'Zero-based position.', 'integer', ['min' => 0]),
                ], idempotent: true),
            self::write('delete_collection', 'Delete a collection',
                'Delete a collection. The recipes in it are kept. This cannot be undone.',
                'DELETE', '/collections/{collection}', [self::path('collection', 'Collection ID (ULID).')], destructive: true, idempotent: true),
            self::write('reorder_collections', 'Reorder collections',
                'Set the display order of the caller\'s collections. Pass the IDs of the collections in the desired order.',
                'PATCH', '/collections/reorder', [
                    self::body('collection_ids', 'Collection IDs in the desired order.', 'id_list', ['required' => true]),
                ], idempotent: true),
            self::write('add_recipe_to_collection', 'Add a recipe to a collection',
                'Add a visible recipe (published, or the caller\'s own) to a collection. Idempotent.',
                'PUT', '/collections/{collection}/recipes/{recipe}', [
                    self::path('collection', 'Collection ID (ULID).'),
                    self::path('recipe', 'Recipe ID (ULID).'),
                ], idempotent: true),
            self::write('remove_recipe_from_collection', 'Remove a recipe from a collection',
                'Remove a recipe from a collection without deleting the recipe. Idempotent.',
                'DELETE', '/collections/{collection}/recipes/{recipe}', [
                    self::path('collection', 'Collection ID (ULID).'),
                    self::path('recipe', 'Recipe ID (ULID).'),
                ], idempotent: true),
        ];
    }

    /**
     * @return array<int, ApiTool>
     */
    private static function socialTools(): array
    {
        return [
            self::write('follow_profile', 'Follow a profile',
                'Follow a public profile. Idempotent. Not possible when either user has blocked the other.',
                'POST', '/profiles/{username}/follow', [self::path('username', 'The profile username.')], idempotent: true),
            self::write('unfollow_profile', 'Unfollow a profile',
                'Stop following a profile the caller currently follows. Idempotent: unfollowing twice has no further effect.',
                'DELETE', '/profiles/{username}/follow', [self::path('username', 'The profile username.')], idempotent: true),
            self::write('update_my_profile', 'Update my profile',
                'Update the caller\'s profile username, camera or biography. The profile picture cannot be changed through MCP. The username is public and must be unique.',
                'PATCH', '/me/profile', [
                    self::body('username', 'Public username (unique).'),
                    self::body('camera_model_id', 'Camera model ID shown on the profile, or null to clear.'),
                    self::body('biography', 'Biography (max 1000 characters).'),
                ], idempotent: true),
        ];
    }

    /**
     * @param  array<int, array<string, mixed>>  $params
     */
    private static function read(string $name, string $title, string $description, string $path, array $params): ApiTool
    {
        return new ApiTool($name, $title, $description, 'GET', $path, $params, [
            'readOnly' => true,
            'destructive' => false,
            'idempotent' => true,
        ]);
    }

    /**
     * @param  array<int, array<string, mixed>>  $params
     */
    private static function write(
        string $name,
        string $title,
        string $description,
        string $method,
        string $path,
        array $params,
        bool $destructive = false,
        bool $idempotent = false,
    ): ApiTool {
        return new ApiTool($name, $title, $description, $method, $path, $params, [
            'readOnly' => false,
            'destructive' => $destructive,
            'idempotent' => $idempotent,
        ]);
    }

    /**
     * @return array<string, mixed>
     */
    private static function path(string $name, string $description): array
    {
        return ['name' => $name, 'in' => 'path', 'type' => 'string', 'required' => true, 'description' => $description];
    }

    /**
     * @param  array<string, mixed>  $extra
     * @return array<string, mixed>
     */
    private static function query(string $name, string $description, string $type = 'string', array $extra = []): array
    {
        return ['name' => $name, 'in' => 'query', 'type' => $type, 'description' => $description, ...$extra];
    }

    /**
     * @param  array<string, mixed>  $extra
     * @return array<string, mixed>
     */
    private static function body(string $name, string $description, string $type = 'string', array $extra = []): array
    {
        return ['name' => $name, 'in' => 'body', 'type' => $type, 'description' => $description, ...$extra];
    }
}
