<?php

namespace Tests\Feature;

use App\Models\CameraModel;
use App\Models\Recipe;
use App\Models\User;
use Database\Seeders\CameraCapabilitySeeder;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Testing\TestResponse;
use Tests\TestCase;

class McpServerTest extends TestCase
{
    use RefreshDatabase;

    private const WRITE_TOOLS = [
        'create_recipe', 'update_recipe', 'delete_recipe', 'publish_recipe', 'copy_recipe', 'like_recipe',
        'unlike_recipe', 'add_recipe_comment', 'delete_comment', 'create_collection', 'update_collection',
        'delete_collection', 'reorder_collections', 'add_recipe_to_collection', 'remove_recipe_from_collection',
        'follow_profile', 'unfollow_profile', 'update_my_profile',
    ];

    private int $rpcId = 0;

    public function test_it_requires_authentication(): void
    {
        $this->postJson('/api/v1/mcp', $this->message('tools/list'))
            ->assertUnauthorized()
            ->assertJsonPath('error.code', 'unauthenticated');
    }

    public function test_initialize_describes_the_server_and_its_capabilities(): void
    {
        $user = User::factory()->create();

        $result = $this->rpc($this->token($user, ['read']), 'initialize', [
            'protocolVersion' => '2025-06-18',
            'capabilities' => [],
            'clientInfo' => ['name' => 'test-client', 'version' => '1.0'],
        ])->assertOk()->json('result');

        self::assertSame('SimRecipes', $result['serverInfo']['name']);
        self::assertArrayHasKey('tools', $result['capabilities']);
        self::assertArrayHasKey('resources', $result['capabilities']);
        self::assertArrayHasKey('prompts', $result['capabilities']);
        self::assertStringContainsString('immutable', $result['instructions']);
    }

    public function test_read_only_tokens_are_only_offered_read_only_tools(): void
    {
        $user = User::factory()->create();

        $readTools = $this->listTools($this->token($user, ['read']));
        $allTools = $this->listTools($this->token($user, ['read', 'write']));

        self::assertCount(12, $readTools);
        self::assertCount(30, $allTools);
        foreach ($readTools as $tool) {
            self::assertTrue($tool['annotations']['readOnlyHint'], $tool['name'].' must be read-only');
        }
        foreach (self::WRITE_TOOLS as $name) {
            self::assertArrayNotHasKey($name, $readTools);
            self::assertArrayHasKey($name, $allTools);
            self::assertFalse($allTools[$name]['annotations']['readOnlyHint']);
        }
        self::assertTrue($allTools['delete_recipe']['annotations']['destructiveHint']);
        self::assertTrue($allTools['publish_recipe']['annotations']['destructiveHint']);
        self::assertFalse($allTools['create_recipe']['annotations']['destructiveHint']);
        self::assertTrue($allTools['like_recipe']['annotations']['idempotentHint']);
        self::assertSame('object', $allTools['create_recipe']['inputSchema']['type']);
        self::assertContains('name', $allTools['create_recipe']['inputSchema']['required']);
        self::assertContains('camera_model_id', $allTools['create_recipe']['inputSchema']['required']);

        foreach ($allTools as $tool) {
            self::assertGreaterThan(40, strlen($tool['description']), $tool['name'].' needs an LLM-oriented description');
            self::assertStringNotContainsStringIgnoringCase('token', $tool['description'].json_encode($tool['inputSchema']));
        }
    }

    public function test_write_only_token_is_not_offered_read_tools_and_cannot_call_them(): void
    {
        $user = User::factory()->create();
        $token = $this->token($user, ['write']);

        $tools = $this->listTools($token);
        self::assertArrayNotHasKey('list_my_recipes', $tools);
        self::assertArrayHasKey('create_collection', $tools);

        $this->callTool($token, 'list_my_recipes')
            ->assertStatus(400)
            ->assertJsonPath('error.message', 'Tool [list_my_recipes] not found.');
    }

    public function test_it_rejects_tokens_without_a_usable_scope(): void
    {
        $user = User::factory()->create();

        $this->rpc($this->token($user, ['unrelated']), 'tools/list')
            ->assertForbidden()
            ->assertJsonPath('error.code', 'insufficient_scope');
    }

    public function test_agent_can_create_read_publish_gate_and_delete_a_private_recipe(): void
    {
        $this->seed(CameraCapabilitySeeder::class);
        $camera = CameraModel::query()->where('slug', 'fujifilm-x-s20')->firstOrFail();
        $user = User::factory()->create();
        $token = $this->token($user, ['read', 'write']);

        $created = $this->toolJson($this->callTool($token, 'create_recipe', [
            'name' => 'Agent Chrome',
            'camera_model_id' => $camera->id,
            'description' => 'Drafted through MCP.',
            'tags' => ['street', 'agent'],
            'settings' => [['setting_key' => 'film_simulation', 'value' => 'REALA ACE']],
        ]));
        $recipeID = $created['data']['id'];
        self::assertSame('private', $created['data']['status']);
        self::assertDatabaseHas('recipes', ['id' => $recipeID, 'user_id' => $user->id]);

        $own = $this->toolJson($this->callTool($token, 'get_recipe', ['recipe' => $recipeID]));
        self::assertSame('Agent Chrome', $own['data']['name']);

        $library = $this->toolJson($this->callTool($token, 'list_my_recipes', ['status' => 'private']));
        self::assertSame([$recipeID], array_column($library['data'], 'id'));

        $published = $this->callTool($token, 'publish_recipe', ['recipe' => $recipeID]);
        $published->assertJsonPath('result.isError', true);
        self::assertSame(422, $this->toolJson($published, true)['http_status']);

        $this->callTool($token, 'delete_recipe', ['recipe' => $recipeID])->assertJsonPath('result.isError', false);
        self::assertDatabaseMissing('recipes', ['id' => $recipeID]);
    }

    public function test_tool_validation_errors_use_the_rest_error_envelope(): void
    {
        $this->seed(CameraCapabilitySeeder::class);
        $camera = CameraModel::query()->where('slug', 'fujifilm-x-s20')->firstOrFail();
        $token = $this->token(User::factory()->create(), ['read', 'write']);

        $error = $this->toolJson($this->callTool($token, 'create_recipe', [
            'name' => 'Invalid',
            'camera_model_id' => $camera->id,
            'settings' => [['setting_key' => 'film_simulation', 'value' => 'Not a simulation']],
        ]), true);

        self::assertSame('validation_failed', $error['error']['code']);
        self::assertSame(422, $error['http_status']);

        $missing = $this->toolJson($this->callTool($token, 'create_recipe', ['name' => 'No camera']), true);
        self::assertSame('validation_failed', $missing['error']['code']);
    }

    public function test_tools_cannot_read_other_users_private_data_or_change_their_resources(): void
    {
        $camera = CameraModel::create(['manufacturer' => 'Fujifilm', 'name' => 'X-S20', 'slug' => 'x-s20']);
        $owner = User::factory()->create();
        $intruder = User::factory()->create();
        $draft = Recipe::create(['user_id' => $owner->id, 'camera_model_id' => $camera->id, 'name' => 'Secret draft']);
        $token = $this->token($intruder, ['read', 'write']);

        $notFound = $this->toolJson($this->callTool($token, 'get_recipe', ['recipe' => $draft->id]), true);
        self::assertSame('not_found', $notFound['error']['code']);

        $forbidden = $this->toolJson($this->callTool($token, 'update_recipe', ['recipe' => $draft->id, 'name' => 'Hijacked']), true);
        self::assertSame('forbidden', $forbidden['error']['code']);
        $this->toolJson($this->callTool($token, 'delete_recipe', ['recipe' => $draft->id]), true);
        self::assertDatabaseHas('recipes', ['id' => $draft->id, 'name' => 'Secret draft']);

        $search = $this->toolJson($this->callTool($token, 'search_recipes'));
        self::assertSame([], $search['data']);
    }

    public function test_path_arguments_cannot_escape_the_declared_endpoint(): void
    {
        $token = $this->token(User::factory()->create(), ['read', 'write']);

        foreach (['../admin/users', 'a/b', '..', 'x?y=1', ''] as $value) {
            $error = $this->toolJson($this->callTool($token, 'get_recipe', ['recipe' => $value]), true);
            self::assertSame('validation_failed', $error['error']['code'], $value);
        }

        $unknown = $this->callTool($token, 'get_admin_user', ['user' => 'x']);
        self::assertArrayHasKey('error', $unknown->json());
    }

    public function test_collection_workflow_and_scope_enforcement_for_restricted_tokens(): void
    {
        $camera = CameraModel::create(['manufacturer' => 'Fujifilm', 'name' => 'X-S20', 'slug' => 'x-s20']);
        $author = User::factory()->create();
        $public = Recipe::create([
            'user_id' => $author->id, 'camera_model_id' => $camera->id, 'name' => 'Public',
            'status' => Recipe::STATUS_PUBLISHED, 'published_at' => now(),
        ]);
        $user = User::factory()->create();
        $token = $this->token($user, ['read', 'write']);

        $collection = $this->toolJson($this->callTool($token, 'create_collection', ['name' => 'Favourites']))['data'];
        $withRecipe = $this->toolJson($this->callTool($token, 'add_recipe_to_collection', [
            'collection' => $collection['id'],
            'recipe' => $public->id,
        ]));
        self::assertSame($public->id, $withRecipe['data']['recipes'][0]['id']);
        $fetched = $this->toolJson($this->callTool($token, 'get_collection', ['collection' => $collection['id']]));
        self::assertCount(1, $fetched['data']['recipes']);

        $readOnly = $this->token($user, ['read']);
        $this->callTool($readOnly, 'delete_collection', ['collection' => $collection['id']])
            ->assertStatus(400)
            ->assertJsonPath('error.message', 'Tool [delete_collection] not found.');
        self::assertDatabaseHas('recipe_collections', ['id' => $collection['id']]);
    }

    public function test_resources_and_prompts_are_listed_and_readable(): void
    {
        $this->seed(CameraCapabilitySeeder::class);
        $token = $this->token(User::factory()->create(), ['read']);

        $uris = array_column($this->rpc($token, 'resources/list')->json('result.resources'), 'uri');
        self::assertContains('simrecipes://cameras', $uris);
        self::assertContains('simrecipes://categories', $uris);

        $templates = array_column($this->rpc($token, 'resources/templates/list')->json('result.resourceTemplates'), 'uriTemplate');
        self::assertContains('simrecipes://recipes/{recipe}', $templates);

        $cameras = $this->rpc($token, 'resources/read', ['uri' => 'simrecipes://cameras'])->json('result.contents.0.text');
        self::assertStringContainsString('X-S20', $cameras);

        $prompts = array_column($this->rpc($token, 'prompts/list')->json('result.prompts'), 'name');
        self::assertEqualsCanonicalizing(
            ['create_recipe_draft', 'find_community_recipe', 'review_recipe_before_publishing'],
            $prompts,
        );
        $prompt = $this->rpc($token, 'prompts/get', [
            'name' => 'create_recipe_draft',
            'arguments' => ['camera' => 'X-S20', 'style' => 'warm street'],
        ])->json('result.messages.0.content.text');
        self::assertStringContainsString('publish_recipe', $prompt);
    }

    public function test_mcp_endpoint_has_its_own_rate_limit(): void
    {
        config(['api.rate_limits.mcp' => 2]);
        $token = $this->token(User::factory()->create(), ['read']);

        $this->rpc($token, 'ping')->assertOk();
        $this->rpc($token, 'ping')->assertOk();
        $this->rpc($token, 'ping')
            ->assertStatus(429)
            ->assertJsonPath('error.code', 'rate_limited')
            ->assertHeader('Retry-After');
    }

    public function test_get_and_delete_on_the_mcp_endpoint_are_not_allowed(): void
    {
        $this->get('/api/v1/mcp')->assertStatus(405);
        $this->delete('/api/v1/mcp')->assertStatus(405);
    }

    /**
     * @param  array<int, string>  $abilities
     */
    private function token(User $user, array $abilities): string
    {
        return $user->createToken('pat:test', $abilities)->plainTextToken;
    }

    /**
     * @param  array<string, mixed>  $params
     * @return array<string, mixed>
     */
    private function message(string $method, array $params = []): array
    {
        return ['jsonrpc' => '2.0', 'id' => ++$this->rpcId, 'method' => $method, 'params' => (object) $params];
    }

    /**
     * @param  array<string, mixed>  $params
     */
    private function rpc(string $token, string $method, array $params = []): TestResponse
    {
        $this->app['auth']->forgetGuards();

        return $this->withToken($token)
            ->withHeaders(['Accept' => 'application/json, text/event-stream'])
            ->postJson('/api/v1/mcp', $this->message($method, $params));
    }

    /**
     * @param  array<string, mixed>  $arguments
     */
    private function callTool(string $token, string $name, array $arguments = []): TestResponse
    {
        return $this->rpc($token, 'tools/call', ['name' => $name, 'arguments' => (object) $arguments]);
    }

    /**
     * @return array<string, array<string, mixed>>
     */
    private function listTools(string $token): array
    {
        $tools = $this->rpc($token, 'tools/list', [])->assertOk()->json('result.tools');

        return array_column($tools, null, 'name');
    }

    /**
     * @return array<string, mixed>
     */
    private function toolJson(TestResponse $response, bool $expectError = false): array
    {
        $response->assertOk();
        self::assertSame($expectError, $response->json('result.isError'), $response->getContent());

        return json_decode($response->json('result.content.0.text'), true, 512, JSON_THROW_ON_ERROR);
    }
}
