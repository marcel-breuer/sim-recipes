# Backend security review

Reviewed on 2026-10-19 against the repository's Laravel API and current GitHub
Advisory Database entry for `GHSA-vfj7-8cjw-p6xm`.

## Access control and sharing

- Recipe creation and mutations require Sanctum authentication. Recipe policies
  enforce ownership and published-recipe immutability; private recipes are
  returned as not found to other users.
- Public recipe and image access checks publication state, hidden/suspended
  accounts, blocks, and image policy authorization before reading storage.
- Recipe copies are created transactionally, retain source provenance, and are
  owned independently by the requesting user.
- Regression coverage is in `RecipeLifecycleTest`, `RecipeCopyTest`,
  `RecipeImageStorageTest`, `RecipeEngagementTest`, and `AuthenticationTest`.

## Uploads and media

- Form Requests restrict recipe uploads to image files of approved formats and
  at most 25 MB each; image count is capped at five per recipe.
- Storage quota is enforced while the owner's row is locked, reducing races
  between simultaneous uploads. Public responses serve sanitized WebP
  derivatives; the original remains owner-only and is unavailable after
  publication.
- `RecipeImageStorageTest` covers count, size, quota, ownership, public/private
  image access, metadata stripping, and deletion behavior.

## Authentication, rate limits, and logs

- Sign in with Apple tokens are verified server-side. Sanctum access tokens
  expire after 30 days by default and logout revokes the active token.
- This repository does not configure an application-level API rate limiter.
  The Coolify ingress rate-limit policy is outside this checkout and must be
  verified separately before relying on edge throttling.
- Request and queue timing logs avoid credentials, user input, SQL, bindings,
  and queued payload contents. Metrics use the container's stderr channel so
  they remain visible through Docker/Coolify logs.

## Dependency advisory

The `braces` advisory affects versions through `3.0.3`. On 2026-10-19 the
GitHub Advisory Database still listed no patched version. The repository's
Dependabot configuration includes npm security updates; the scheduled
`monitor-braces-advisory` workflow also checks the authoritative advisory weekly
and comments on issue #141 once a patched version is listed. Reassess the
transitive dependency and update the lockfile when that notification arrives.
