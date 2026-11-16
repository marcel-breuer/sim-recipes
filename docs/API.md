# API conventions

The machine-readable contract is maintained in [`docs/openapi.json`](openapi.json)
(OpenAPI 3.1, every `/api/v1` operation). A feature test
(`ApiContractTest`) fails when the registered routes, their authentication
requirement or token scope drift from the contract, when a `$ref` does not
resolve, or when a component is unused. Changes to versioned paths, error
envelopes, pagination or authentication must update that contract and the
client transport tests in the same change. The Model Context Protocol server
built on this API is described in [`docs/MCP.md`](MCP.md).

The Laravel application exposes JSON endpoints under /api/v1. The version
prefix is part of the public contract and must be retained for compatible
changes.

## Responses and errors

Successful single-resource responses use an explicit API Resource and the
standard data envelope. Collection endpoints return a data array plus
pagination metadata and links. New collection endpoints should use cursor
pagination unless a different strategy is required by the product behavior.

API errors use this shape:

    {
      "error": {
        "code": "validation_failed",
        "message": "The given data was invalid.",
        "details": {
          "field": ["The field is required."]
        }
      }
    }

Validation belongs at explicit Form Request boundaries. Authorization belongs
in policies or gates and must be enforced server-side. Eloquent models are not
serialized directly as public API responses.

## Authentication and token scopes

Authenticated endpoints expect `Authorization: Bearer <token>`. Tokens are
Laravel Sanctum personal access tokens stored hashed in `personal_access_tokens`.

| Token kind | How it is issued | Abilities | Typical use |
| --- | --- | --- | --- |
| First-party session | `POST /api/v1/auth/apple` (Sign in with Apple) | `*` (unrestricted) | The iOS app |
| Personal access token | `POST /api/v1/me/tokens` from a first-party session | `read` and/or `write` | Scripts, automation, MCP clients |

Scope rules, enforced by one middleware for every authenticated route:

- `read` allows safe requests (`GET`); `write` allows mutations (`POST`, `PUT`,
  `PATCH`, `DELETE`). The two scopes are independent: a `write` token cannot
  read, so issue `["read", "write"]` for full access to the owner's own data.
- `POST /auth/logout` works with any valid token.
- Token management (`/me/tokens`) and all `/admin/*` endpoints require an
  unrestricted first-party token. A personal access token can never mint other
  tokens or perform administrative actions, even for an administrator account.
- A token that lacks the scope receives `403` with
  `error.code = insufficient_scope` and `error.details.required_scopes`.
- Authorization is not widened by scopes: after the scope check, the same
  policies as for the iOS app decide what the account may do.
- Public endpoints work without a token. When a valid bearer token with the
  `read` scope is sent to a public endpoint (for example `GET /recipes/{id}`),
  the caller is recognised, so owners can read their own private recipes and
  block lists apply. Invalid, expired or write-only tokens are treated as
  anonymous there and never cause an error.
- Suspended accounts are rejected with `401` on every authenticated route.

Personal access tokens:

    curl -X POST https://api.example.com/api/v1/me/tokens \
      -H "Authorization: Bearer $SESSION_TOKEN" -H "Content-Type: application/json" \
      -d '{"name": "Claude Desktop", "abilities": ["read", "write"], "expires_in_days": 90}'

    {
      "data": {
        "id": "7",
        "name": "Claude Desktop",
        "abilities": ["read", "write"],
        "last_used_at": null,
        "expires_at": "2027-02-14T09:30:00.000000Z",
        "created_at": "2026-11-16T09:30:00.000000Z",
        "token": "7|…shown once…"
      }
    }

The secret `token` is returned exactly once, in this response. It is never
stored in clear text, never returned by `GET /me/tokens` and must not be logged.
Tokens expire after `expires_in_days` (default 30, maximum 365); an account can
hold at most 10 personal access tokens (`409 conflict` beyond that). `GET
/me/tokens` lists token metadata with cursor pagination and `DELETE
/me/tokens/{id}` revokes a token immediately.

Sign in with Apple remains the only way to obtain a first-party session. There
is deliberately no password or API-key login, so automation always acts as an
account that signed in through Apple and chose to delegate access.

## Conventions

**Envelopes.** Single resources and action results are `{"data": {...}}`.
Collections are `{"data": [...], "links": {...}, "meta": {...}}` (the
non-paginated lists `GET /cameras`, `GET /categories`, `GET /collections` and
`GET /recipes/{recipe}/similar` return only `data`; they are small and bounded).

**Pagination.** New collection endpoints use cursor pagination:
`?per_page=` (1-100, default 20) and `?cursor=` with the opaque value from
`meta.next_cursor`; `next_cursor` is `null` on the last page. The existing
community feed and comment lists keep page-number pagination (`?page=`,
`meta.current_page`, `meta.last_page`) for iOS compatibility; admin lists use
page numbers with `per_page` up to 50.

**Error codes.** Every error uses the envelope above with a stable `code`:

| HTTP | `error.code` | Meaning |
| --- | --- | --- |
| 400 | `bad_request` | Malformed request |
| 401 | `unauthenticated` | Missing, invalid, expired or revoked token, or a suspended account |
| 403 | `forbidden` | A policy denies the action (not the owner, published recipe is immutable, not an admin) |
| 403 | `insufficient_scope` | The token lacks `read`, `write` or full access; see `details.required_scopes` |
| 404 | `not_found` | Missing, or not visible to the caller (private data is never confirmed to exist) |
| 405 | `method_not_allowed` | |
| 409 | `conflict`, `idempotency_in_progress` | State conflict, token limit reached, or an identical idempotent request is still running |
| 422 | `validation_failed` | Field errors in `error.details` |
| 422 | `unprocessable`, `invalid_idempotency_key`, `idempotency_key_reused` | The request is well-formed but cannot be processed |
| 429 | `rate_limited` | See rate limits; honour the `Retry-After` header |
| 5xx | `server_error` | No internal details are exposed |

**Rate limits.** Per minute and per token (anonymous requests per IP address):
120 reads (`GET`), 60 writes, 10 Sign in with Apple attempts per IP, and a
separate bucket of 60 MCP requests. Limits are configurable with
`API_RATE_LIMIT_READ`, `API_RATE_LIMIT_WRITE`, `API_RATE_LIMIT_AUTH` and
`API_RATE_LIMIT_MCP`. Exceeding a limit returns `429` and `Retry-After`.

**Idempotency.** Creating endpoints (`POST /recipes`, `/recipes/{id}/copy`,
`/recipes/{id}/comments`, `/collections` and the report endpoints) honour the
`Idempotency-Key` header (8-128 characters of letters, digits and `. _ : -`).
The first successful response is stored for 24 hours per user and key and
replayed for an equivalent retry with the header `Idempotent-Replayed: true`;
reusing the key with a different method, path or payload returns `422
idempotency_key_reused`. Failed responses are not stored, so a corrected retry
may reuse the key. `PUT`/`DELETE` operations (likes, follows, collection
membership, deletes) are naturally idempotent. Without the header, behaviour is
unchanged.

**Sensitive data.** Responses never contain secrets other than the one-time
token above, authorization headers are never logged, and image URLs are API URLs
that are authorized per request.

## Camera capability endpoints

Camera definitions are public and data-driven. `GET /api/v1/cameras` returns
supported camera models with their capabilities. A single camera can be read
by ULID or slug through `GET /api/v1/cameras/{camera}`; capabilities can also
be requested directly with `GET /api/v1/cameras/{camera}/capabilities`.

Each capability includes its setting key, display label, value type, allowed
values or ranges, transport identifier, and custom-slot metadata. Camera
resources also expose `unsupported_recipe_settings` and `transport_metadata`.
Capabilities include an `evidence` object with a level (`catalog_only`,
`manufacturer_documented`, or `camera_verified`), an optional source, the
verified firmware, and verification time. Existing catalogue entries default
to `catalog_only`; this records capability data, not proof of camera transfer.
`camera_verified` requires a source, firmware version, and verification time.
The current seeded models are the X-S20 (`C1`–`C4`) and X-T5 (`C1`–`C7`).
Clients should render controls from this response rather than hard-coding a
camera's setting list. Changing a private recipe's camera model revalidates
all existing settings against the target model; incompatible values are
rejected without changing the recipe.

`GET /api/v1/categories` returns the predefined recipe categories used by the
iOS editor. Category IDs from this response are submitted with recipe writes;
free-form tags remain plain strings.

## Community recipes

`GET /api/v1/recipes` is public and returns only published recipes. It uses
page-number pagination with a default of 20 items and accepts these composable
query parameters:

- `feed=popular|newest` (defaults to `popular`);
- `search` for recipe name, description, recommendation, or tag text;
- `camera_model_id` and `film_simulation`;
- `compatibility_evidence=manufacturer_documented|camera_verified`, which
  requires `camera_model_id` and returns only recipes whose every setting has
  at least the requested evidence level;
- repeated `subjects[]`, `lighting[]`, and `looks[]` values to find recipes
  with an example photo labeled for the selected shooting context;
- repeated `categories[]` and `tags[]` values, matched by ID or slug;
- `per_page` up to the configured API maximum.

Filters are combined with AND semantics between filter types. Multiple values
within a category, tag, or context facet match any selected value. Context
facets are combined with AND semantics, and all selected facets must be present
on the same example photo. Ordering has stable ID tie-breakers so adjacent
pages remain deterministic during normal browsing.

Recipe image uploads may include an `example_context` JSON array aligned by
index with `images[]`. Each item is null or an object with `subjects`,
`lighting`, and `looks` arrays. These labels are supplied by the recipe author;
the application does not infer scene content or color character from the photo.
Recognized subject values are `street`, `portrait`, `landscape`, `architecture`,
`nature`, `wildlife`, `travel`, `automotive`, `night`, `low_light`, `indoor`,
`food`, `everyday`, `documentary`, and `close_up`. Lighting values are
`daylight`, `golden_hour`, `blue_hour`, `overcast`, `open_shade`, `backlit`,
`artificial`, `mixed`, `low_light`, and `studio`. Look values are `warm`,
`neutral`, `cool`, `monochrome`, `vibrant`, `muted`, `cinematic`, and `vintage`.
The same labels are returned as `images[].example_context`, copied with a recipe,
and available to search and filter saved recipes offline.

## Community engagement

- `POST /api/v1/recipes/{recipe}/view` records a public view. Authenticated
  viewers are deduplicated per recipe for 15 minutes. Anonymous clients may
  provide a stable `X-Anonymous-Key`; otherwise the API derives a short-lived
  actor key from the request context.
- Authenticated users can `POST` and `DELETE`
  `/api/v1/recipes/{recipe}/like`. Both operations are idempotent and only
  published recipes can be liked.
- Successful copy/download application flows record a `recipe_downloads` event
  through the engagement service and increment only the source recipe counter.
- Authenticated users copy a public recipe with `POST
  /api/v1/recipes/{recipe}/copy`. The response is the new private recipe in the
  user's normal library, including `provenance.source_recipe_id` and
  `provenance.source_author_id`. Metadata, settings, relations, and stored image
  representations are copied transactionally.

Retryable authenticated mutations should send a stable `Idempotency-Key` header
for the logical operation (for example, one key per local draft save or copy
request). The server contract must treat a repeated key and equivalent payload
as the original result, so an offline retry cannot create duplicate recipes,
copies, likes, or engagement events. A changed payload must be rejected rather
than silently reusing the earlier result.

Authenticated users can follow and unfollow a public profile with `POST` and
`DELETE /profiles/{username}/follow`. Profile responses include follower and
following counts and the authenticated viewer's `is_following` state. Following
is unavailable when either user has blocked the other.

Authenticated users manage their personal collections with `GET` and `POST
/collections`, `PATCH`/`DELETE /collections/{collection}`, and
`PATCH /collections/reorder`. Recipe membership is idempotently added or
removed with `PUT`/`DELETE /collections/{collection}/recipes/{recipe}`. Only
the owning user can read or mutate personal collections. Public profile
responses expose only collections marked public and filter their members to
published, visible recipes, so private drafts never cross the profile boundary.

The default popularity strategy scores likes × 3, downloads × 5, and views ×
1. It is bound behind a replaceable `PopularityRanking` service so the formula
can change without a database migration.

Authenticated users can create comments on published recipes with `POST
/recipes/{recipe}/comments`. Comments are listed with page-number pagination
through `GET /recipes/{recipe}/comments`; hidden, deleted, suspended-user, and
blocked-user comments are omitted. Authors can soft-delete their own comments
with `DELETE /comments/{comment}`.

Recipe create and update multipart requests may include a JSON-encoded
`capture_metadata` array aligned by index with the uploaded `images[]` files.
Each item is either `null` or a validated capture-data object. The API only
stores allowlisted fields. A location is removed unless `location_shared` is
explicitly `true`; coordinates are range-validated before storage. Image
resources return the stored capture metadata, with the same location consent
check applied when building the response.

Recipe image URLs are API URLs rather than direct storage URLs. The
image endpoint authorizes access against the owning recipe, serves originals
or generated `thumbnail`/`detail` variants, and keeps private recipe images
behind the same ownership boundary. Private recipe owners may delete images;
published images are immutable.

## Safety and moderation

`GET /api/v1/support` is public and returns the current support email,
community-standards URL, and privacy-policy URL.

Authenticated users can report published recipes, recipe images, and profiles
with `POST /recipes/{recipe}/reports`,
`POST /recipe-images/{recipeImage}/reports`, and
`POST /profiles/{username}/reports`. Published recipe comments can be reported
with `POST /comments/{comment}/reports`; comment text uses the same deterministic
pre-publication screen as recipe text. They can block and unblock profiles with
`POST`/`DELETE /profiles/{username}/block` or the equivalent user-ID routes.
Blocked users and their public recipes are omitted from the blocker's feed and
detail views.

Administrators can review paginated reports with `GET /admin/reports` and
resolve them with `PATCH /admin/reports/{report}` using `hide_content`,
`suspend_user`, `restore_content`, or `dismiss`. Recipe text is screened before
storage; image moderation remains report- and admin-review driven.

## Personal library and collections

`GET /api/v1/me/recipes` lists the caller's own library: private drafts,
published recipes and copies of community recipes, newest first, with cursor
pagination. It accepts `status=private|published`, `search` (name, description,
recommendation), `camera_model_id`, `per_page` and `cursor`. Recipes hidden by
moderation are omitted.

    curl "https://api.example.com/api/v1/me/recipes?status=private&per_page=2" \
      -H "Authorization: Bearer $TOKEN"

    {
      "data": [ { "id": "01k…", "name": "Warm Street", "status": "private", "…": "…" } ],
      "links": { "first": null, "last": null, "prev": null, "next": "https://api.example.com/api/v1/me/recipes?cursor=eyJ…" },
      "meta": { "path": "https://api.example.com/api/v1/me/recipes", "per_page": 2, "next_cursor": "eyJ…", "prev_cursor": null }
    }

`GET /api/v1/recipes/{recipe}` returns the caller's own private recipes when the
request carries a bearer token with the `read` scope. `GET
/api/v1/collections/{collection}` returns one of the caller's collections;
other users' collections return `403`. Collection names are unique per user
(`422 validation_failed` on duplicates).

## Endpoint reference

All paths are relative to `/api/v1`. "Scope" is the token scope required:
`public` needs no token, `read`/`write` are the personal-access-token scopes,
and `full` needs an unrestricted first-party token. Request and response
schemas, parameters and all error responses are in
[`openapi.json`](openapi.json).

| Method and path | Scope | Purpose |
| --- | --- | --- |
| `GET /health`, `GET /health/ready`, `GET /support` | public | Liveness, readiness (database, Redis), support contacts |
| `POST /auth/apple` | public | Sign in with Apple; returns the first-party token |
| `POST /auth/logout` | any | Revoke the current token |
| `GET /cameras`, `/cameras/{camera}`, `/cameras/{camera}/capabilities`, `/categories` | public | Camera and category catalogues |
| `GET /recipes` | public | Community feed with filters (page pagination) |
| `GET /recipes/{recipe}`, `/recipes/{recipe}/similar`, `/recipes/{recipe}/comments` | public (+read) | Detail, similar recipes, comments; owners also read their private recipes with a `read` token |
| `GET /recipe-images/{image}` | public (+read) | Image bytes (`?variant=thumbnail\|detail\|original`), authorized via the recipe |
| `POST /recipes/{recipe}/view` | public | Record a view (deduplicated) |
| `GET /me/recipes` | read | Personal library (cursor pagination) |
| `POST /recipes` | write | Create a private recipe (JSON, or multipart with images) |
| `PATCH /recipes/{recipe}` (`POST` alias) | write | Update a private recipe |
| `DELETE /recipes/{recipe}` | write | Delete a private recipe |
| `POST /recipes/{recipe}/publish` | write | Publish (irreversible) |
| `POST /recipes/{recipe}/copy` | write | Copy a published recipe into the library |
| `DELETE /recipe-images/{image}` | write | Delete an image of a private recipe |
| `POST`/`DELETE /recipes/{recipe}/like` | write | Like and unlike (idempotent) |
| `POST /recipes/{recipe}/comments`, `DELETE /comments/{comment}` | write | Comment and delete own comment |
| `GET /collections`, `GET /collections/{collection}` | read | Own collections |
| `POST /collections`, `PATCH /collections/{collection}`, `PATCH /collections/reorder`, `DELETE /collections/{collection}` | write | Manage collections |
| `PUT`/`DELETE /collections/{collection}/recipes/{recipe}` | write | Collection membership (idempotent) |
| `GET /profiles/{username}` | public (+read) | Public profile |
| `GET /me/profile`; `PATCH /me/profile` (`POST` alias) | read; write | Own profile, create or update (multipart for the picture) |
| `POST`/`DELETE /profiles/{username}/follow` | write | Follow and unfollow |
| `POST`/`DELETE /profiles/{username}/block`, `/users/{user}/block` | write | Block and unblock |
| `POST …/reports` for recipes, comments, images, profiles and users | write | Report content |
| `GET`/`POST /me/tokens`, `DELETE /me/tokens/{token}` | full | Personal access tokens |
| `GET /admin/users`, `/admin/users/{user}`, `/admin/recipes/{recipe}`, `/admin/reports`; `PATCH /admin/users/{user}/suspension`, `/admin/reports/{report}` | full + admin | Moderation |
| `POST /mcp` | read or write | Model Context Protocol server, see [`MCP.md`](MCP.md) |

Example: create a private recipe and publish-check it.

    curl -X POST https://api.example.com/api/v1/recipes \
      -H "Authorization: Bearer $TOKEN" -H "Idempotency-Key: draft-2026-11-16-001" \
      -H "Content-Type: application/json" \
      -d '{"name": "Warm Street", "camera_model_id": "01k…", "tags": ["street"],
           "settings": [{"setting_key": "film_simulation", "value": "Classic Chrome"}]}'

    # 422: settings that the camera does not allow are rejected
    {"error": {"code": "validation_failed", "message": "The given data was invalid.",
               "details": {"settings": ["…"]}}}

## UI capability coverage

Every capability of the iOS app and of `PROJECT_SPEC.md` has an authorized REST
equivalent: browsing, searching, filtering and viewing community recipes and
profiles; the personal library (`/me/recipes`) and its create, edit, delete,
publish, copy and duplicate flows; images and example-photo labels; likes,
views, comments, follows, blocks and reports; collections; the profile; camera
capabilities; and administrator moderation.

Documented exclusions:

- **Camera transfer over USB-C** happens on the device through `CameraService`;
  it has no server-side equivalent. The API only provides the capability data.
- **Account deletion** is not part of the current product specification, so no
  endpoint exists. It is not invented here; it should be specified first.
- **Sign in with Apple** needs an Apple-issued identity token and therefore
  cannot be performed by an unattended agent. Automation uses personal access
  tokens delegated by a signed-in user.
- **Moderation actions** (`/admin/*`) are available over REST to administrators
  with an unrestricted session only, and are intentionally not exposed through
  personal access tokens or MCP.
