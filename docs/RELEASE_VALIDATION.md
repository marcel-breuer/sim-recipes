# Release-candidate validation

This document is the release checklist for the functional MVP. It separates
repeatable local checks from validations that require macOS, Apple services,
Coolify, or a physical Fujifilm X-S20.

## Automated local checks

Run these checks from the repository root:

```sh
cd backend
vendor/bin/pint --test
vendor/bin/phpstan analyse --no-progress
```

Run the feature and unit tests with the PHP 8.4 backend image and a PostgreSQL
17 test database:

```sh
docker run --rm \
  --network sim-recipes_default \
  -v "$PWD:/var/www/html" \
  -w /var/www/html \
  -e APP_ENV=testing \
  -e DB_CONNECTION=pgsql \
  -e DB_HOST=postgres \
  -e DB_PORT=5432 \
  -e DB_DATABASE=sim_recipes_test \
  -e DB_USERNAME=sim_recipes \
  -e DB_PASSWORD=sim_recipes_test_password \
  sim-recipes-api:local vendor/bin/phpunit --colors=never
```

Validate the single deployment definition without starting services:

```sh
cp docker/.env.example docker/.env
docker compose --env-file docker/.env \
  -f docker/docker-compose.yml config --quiet
```

The backend suite covers authentication, recipe lifecycle and immutability,
images and quotas, community discovery, engagement accounting, copying and
provenance, moderation, blocking, authorization, and database constraints.

## Functional MVP checklist

| Area | Evidence or validation | Status |
| --- | --- | --- |
| Anonymous discovery | `CommunityRecipeFeedTest`, `ProfileTest`, and API feed tests | Pass locally |
| Sign in with Apple boundary | `AuthenticationTest` with signed test identity tokens | Pass locally; live Apple credentials still required |
| Private recipe creation/editing | `RecipeLifecycleTest` and `RecipeImageStorageTest` | Pass locally |
| Immutable publication | `RecipeLifecycleTest` and publication-time moderation coverage | Pass locally |
| Copy/download and provenance | `RecipeCopyTest` and engagement tests | Pass locally |
| Offline library and image cache | `SimRecipesTests` on an iOS simulator | Requires macOS/Xcode |
| Camera discovery/read path | Camera service unit coverage and real-device smoke test | Real X-S20 required |
| Camera recipe write/verification | Hardware transfer test with a supported X-S20 firmware version | Blocked until protocol encodings are verified |
| Coolify deployment | Compose validation, image build, migration, health, and public API smoke test | Deployment environment required |

## Deployment smoke test

For a release candidate, configure `docker/docker-compose.yml` in Coolify
with runtime values from `docker/README.md`. Confirm that:

1. `postgres` and `redis` have no public ports.
2. `api` completes migrations and reports healthy on `/api/v1/health`.
3. `queue` and `scheduler` reach running state after `api` is healthy.
4. The API can read and write image files in the persistent `storage_data` volume.
5. A private recipe image is not accessible without authorization.
6. A published recipe image is accessible through the versioned API endpoint.
7. A deployment restart preserves PostgreSQL, Redis, and image-storage data.

Do not use production credentials in local validation. Coolify secrets belong in
the deployment environment and must not be copied into this repository.

## Hardware validation record

Before claiming the camera transfer acceptance criterion, record the X-S20
firmware version, iPhone/iOS version, cable, camera USB mode, and the result of
each C1-C4 read/write/read-back attempt. The current adapter intentionally
refuses to encode recipe writes while the vendor-property encodings remain
unverified. It must continue to report that limitation rather than claim a
successful transfer.

## Known release limitations

- Native iOS build and tests require a macOS runner with Xcode and an available
  iPhone Simulator.
- Live Sign in with Apple requires configured Apple credentials and cannot be
  fully exercised by the local token-verification tests.
- X-S20 recipe writes remain unavailable until real-device protocol values are
  verified; discovery and safe read-only behavior are still testable separately.
- Coolify and real-device smoke tests require protected deployment/hardware
  environments and are not substitutes for local unit or feature tests.
