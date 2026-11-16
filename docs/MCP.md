# MCP server

SimRecipes exposes a [Model Context Protocol](https://modelcontextprotocol.io)
server so AI assistants can read community recipes and manage the signed-in
user's own library. It is a thin layer over the REST API
([`API.md`](API.md), [`openapi.json`](openapi.json)): there is no second code
path for business logic or authorization.

- Endpoint: `POST /api/v1/mcp` (Streamable HTTP, JSON-RPC 2.0, stateless).
  `GET` and `DELETE` return `405`; there are no server-initiated streams.
- Implementation: `laravel/mcp`, server class `App\Mcp\Servers\SimRecipesServer`.
- Authentication: `Authorization: Bearer <personal access token>` with the
  `read` and/or `write` scope. Without a valid token the endpoint returns `401`.

## How it works

Every tool is a typed facade over exactly one REST endpoint. When a tool runs,
the server dispatches an in-process request to that `/api/v1` route with the
caller's own bearer token. Consequently the MCP layer reuses, unchanged:
token authentication, suspended-account checks, token scopes, rate limits,
Form Request validation, policies (ownership, visibility, immutability of
published recipes, blocks), the safety screening of text, and the API
Resources. A bug fix or rule change in the REST API applies to MCP
automatically, and MCP cannot grant anything REST would deny. Tool arguments
are whitelisted from the tool definition and path arguments must be plain
identifiers (`^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$`), so a client cannot inject
extra fields or reach other routes. Administrator, token-management, image
upload, report and block operations are not exposed at all.

## Setup

Create a personal access token in the SimRecipes app session (or with the REST
API) with the smallest scope you need, ideally with a short expiry:

    curl -X POST https://api.example.com/api/v1/me/tokens \
      -H "Authorization: Bearer $SESSION_TOKEN" -H "Content-Type: application/json" \
      -d '{"name": "MCP read-only", "abilities": ["read"], "expires_in_days": 30}'

Store the returned `token` in your client's secret store; it is shown once.

**Claude Code**

    claude mcp add --transport http simrecipes https://api.example.com/api/v1/mcp \
      --header "Authorization: Bearer $SIMRECIPES_TOKEN"

**Claude Desktop** (and other clients that only speak stdio) through the
`mcp-remote` bridge, in `claude_desktop_config.json`:

    {
      "mcpServers": {
        "simrecipes": {
          "command": "npx",
          "args": ["mcp-remote", "https://api.example.com/api/v1/mcp",
                   "--header", "Authorization: Bearer ${SIMRECIPES_TOKEN}"],
          "env": { "SIMRECIPES_TOKEN": "<token>" }
        }
      }
    }

**Cursor / VS Code / other HTTP-capable clients**: add a server of type
`http` with the URL above and an `Authorization` header.

**Manual check**

    curl -s https://api.example.com/api/v1/mcp \
      -H "Authorization: Bearer $SIMRECIPES_TOKEN" \
      -H "Content-Type: application/json" -H "Accept: application/json, text/event-stream" \
      -d '{"jsonrpc":"2.0","id":1,"method":"tools/call","params":{"name":"search_recipes","arguments":{"search":"street","per_page":3}}}'

For local development use `http://localhost:8080/api/v1/mcp` (or your `APP_URL`).
Browser-originated requests are accepted only from `localhost` and the
configured `APP_URL` (Origin validation).

## Permission model

| Token scope | Tools offered in `tools/list` | Notes |
| --- | --- | --- |
| `read` | the 12 read-only tools, resources, prompts | Cannot change anything |
| `write` | the 18 write tools | Cannot read; combine with `read` for normal use |
| `read` + `write` | all 30 tools | Acts as the user, bounded by the same policies as the app |

- Tools the token cannot use are not listed and cannot be called (unknown tool).
  Scopes are enforced again by the REST layer on every call.
- Every tool carries MCP annotations: `readOnlyHint` (true for read tools),
  `destructiveHint` (true for `delete_*` and `publish_recipe`), `idempotentHint`
  (true when repeating the call has no further effect) and `openWorldHint:
  false`. Well-behaved clients ask the user before running non-read-only or
  destructive tools.
- Tools act only on the token owner's data. Another user's private recipe is
  `not_found`; changing it is `forbidden`; published recipes are immutable.
- The MCP endpoint has its own rate-limit bucket (60 requests per minute per
  token) in addition to the REST read/write limits that every tool call
  consumes. Over-limit requests return `429` with `Retry-After`.

## Tool catalogue

Results are the REST JSON (`{"data": …}`) as text content. Failures are tool
errors (`isError: true`) whose text is the REST error envelope plus
`http_status`, for example `{"error":{"code":"validation_failed","details":{…}},
"http_status":422}`.

**Read tools** (`read` scope)

| Tool | REST endpoint | Purpose |
| --- | --- | --- |
| `list_cameras` | `GET /cameras` | Supported cameras and capabilities |
| `get_camera` | `GET /cameras/{camera}` | One camera: setting keys, allowed values, evidence |
| `list_categories` | `GET /categories` | Recipe categories |
| `search_recipes` | `GET /recipes` | Community search with all feed filters and `page` |
| `get_recipe` | `GET /recipes/{recipe}` | Recipe detail (public or own private) |
| `find_similar_recipes` | `GET /recipes/{recipe}/similar` | Similar published recipes |
| `list_recipe_comments` | `GET /recipes/{recipe}/comments` | Comments |
| `get_profile` | `GET /profiles/{username}` | Public profile |
| `get_my_profile` | `GET /me/profile` | Own profile |
| `list_my_recipes` | `GET /me/recipes` | Own library, cursor pagination |
| `list_my_collections` | `GET /collections` | Own collections |
| `get_collection` | `GET /collections/{collection}` | One own collection |

**Write tools** (`write` scope)

| Tool | REST endpoint | Hints |
| --- | --- | --- |
| `create_recipe` | `POST /recipes` | Creates a private recipe (no images) |
| `update_recipe` | `PATCH /recipes/{recipe}` | Private recipes only; idempotent |
| `delete_recipe` | `DELETE /recipes/{recipe}` | Destructive; private recipes only |
| `publish_recipe` | `POST /recipes/{recipe}/publish` | Destructive: irreversible, needs an image |
| `copy_recipe` | `POST /recipes/{recipe}/copy` | New private copy with provenance |
| `like_recipe`, `unlike_recipe` | `POST`/`DELETE /recipes/{recipe}/like` | Idempotent |
| `add_recipe_comment` | `POST /recipes/{recipe}/comments` | Public text |
| `delete_comment` | `DELETE /comments/{comment}` | Destructive; own comments |
| `create_collection`, `update_collection`, `reorder_collections` | `POST`/`PATCH /collections…` | |
| `delete_collection` | `DELETE /collections/{collection}` | Destructive |
| `add_recipe_to_collection`, `remove_recipe_from_collection` | `PUT`/`DELETE /collections/{collection}/recipes/{recipe}` | Idempotent |
| `follow_profile`, `unfollow_profile` | `POST`/`DELETE /profiles/{username}/follow` | Idempotent |
| `update_my_profile` | `PATCH /me/profile` | Username, camera, biography |

Input schemas (JSON Schema, with LLM-oriented descriptions and enums) are
published through `tools/list`; they mirror the REST validation, which remains
authoritative.

Example, creating a draft:

    {"name": "create_recipe", "arguments": {
      "name": "Warm Street", "camera_model_id": "01k…",
      "tags": ["street"],
      "settings": [{"setting_key": "film_simulation", "value": "Classic Chrome"}]}}

**Resources** (read-only context, fetched with the caller's visibility)

| URI | Content |
| --- | --- |
| `simrecipes://cameras` | Camera catalogue with capabilities |
| `simrecipes://categories` | Category catalogue |
| `simrecipes://recipes/{recipe}` (template) | One recipe as JSON |

**Prompts**

| Prompt | Purpose |
| --- | --- |
| `create_recipe_draft` (`camera`, `style`) | Draft a valid private recipe from capabilities; never publishes |
| `find_community_recipe` (`request`, `camera?`) | Find and compare community recipes; copying only on request |
| `review_recipe_before_publishing` (`recipe_id`) | Completeness checklist before the irreversible publish |

## Security notes

- Use the least privilege and a short expiry: `read` for browsing assistants,
  `read`+`write` only for assistants that should manage your library. Revoke a
  token with `DELETE /api/v1/me/tokens/{id}`; revocation is immediate.
- A personal access token cannot create tokens or reach admin endpoints, so a
  leaked MCP token cannot escalate. Suspended accounts lose access at once.
- Tokens, authorization headers and image URLs are never written to logs, are
  not part of any tool description or result, and the one-time token secret is
  never returned by a tool.
- Treat recipe text, comments and profile fields as untrusted input: they are
  user-generated and may contain instructions aimed at AI agents. Clients should
  not let such text trigger write tools without user confirmation. The server
  instructions tell agents to confirm before irreversible actions
  (`publish_recipe`, `delete_*`), but only the client can enforce a prompt.
- Images cannot be uploaded and profile pictures cannot be changed through MCP;
  upload and storage-quota rules stay on the REST multipart endpoints.
- Use HTTPS in production. The endpoint validates the `Origin` header against
  `APP_URL` and localhost to resist DNS-rebinding from browsers.
