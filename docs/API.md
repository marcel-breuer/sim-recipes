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

Recipe image URLs are API URLs rather than direct object-storage URLs. The
image endpoint authorizes access against the owning recipe, serves originals
or generated `thumbnail`/`detail` variants, and keeps private recipe images
behind the same ownership boundary. Private recipe owners may delete images;
published images are immutable.
