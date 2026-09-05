# API conventions

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

## Authentication preparation

The auth.api middleware alias reserves the API authentication boundary. The
Sign in with Apple implementation will configure the concrete API guard and
token/session lifecycle in the authentication issue; public routes must not
assume an authenticated user.

## Camera capability endpoints

Camera definitions are public and data-driven. `GET /api/v1/cameras` returns
supported camera models with their capabilities. A single camera can be read
by ULID or slug through `GET /api/v1/cameras/{camera}`; capabilities can also
be requested directly with `GET /api/v1/cameras/{camera}/capabilities`.

Each capability includes its setting key, display label, value type, allowed
values or ranges, transport identifier, and custom-slot metadata. Clients
should render controls from this response rather than hard-coding a camera's
setting list.

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
- repeated `categories[]` and `tags[]` values, matched by ID or slug;
- `per_page` up to the configured API maximum.

Filters are combined with AND semantics between filter types. Multiple values
within a category or tag filter match any selected value. Ordering has stable
ID tie-breakers so adjacent pages remain deterministic during normal browsing.

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
  The copy endpoint is defined by the recipe-copy issue.

The default popularity strategy scores likes × 3, downloads × 5, and views ×
1. It is bound behind a replaceable `PopularityRanking` service so the formula
can change without a database migration.

Recipe image URLs are API URLs rather than direct object-storage URLs. The
image endpoint authorizes access against the owning recipe, serves originals
or generated `thumbnail`/`detail` variants, and keeps private recipe images
behind the same ownership boundary. Private recipe owners may delete images;
published images are immutable.
