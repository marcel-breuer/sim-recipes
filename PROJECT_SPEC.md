# SimRecipes MVP Specification

## 1. Product vision

SimRecipes is an iOS-first community application for Fujifilm film-simulation recipes. It combines recipe creation, discovery, personal offline storage, community sharing, and direct transfer of recipe settings to supported Fujifilm cameras over USB-C.

The MVP supports the Fujifilm X-S20. The architecture must support adding further Fujifilm camera models without redesigning the recipe domain model.

## 2. MVP users and access

### Anonymous users
Anonymous users can:
- browse public recipes;
- view popular and newest recipes;
- search recipes;
- filter by supported camera model, film simulation, categories, and tags;
- view recipe details;
- view public user profiles.

### Authenticated users
Authentication uses Sign in with Apple.

Authenticated users can additionally:
- create private recipes;
- edit and delete private recipes;
- publish recipes;
- copy/download community recipes into their own library;
- duplicate recipes;
- like public recipes;
- transfer locally available recipes to a supported camera;
- maintain a profile.

## 3. User profile

A profile contains:
- username;
- optional profile image;
- optional camera model;
- optional biography;
- published recipes.

## 4. Recipe lifecycle

### Private recipe
A private recipe is owned by one user and can be edited or deleted.

### Published recipe
Publishing creates an immutable public version. A published recipe cannot be edited or deleted by the author in the MVP. Any subsequent change requires duplicating the recipe and publishing the copy as a new recipe.

### Community copy/download
Saving or downloading a public recipe creates an account-owned copy. The copy appears in the same personal recipe library as recipes created by the user. There is no separate "Downloaded Recipes" section.

The system should preserve provenance, including the source recipe and source author when applicable.

## 5. Recipe metadata

Each recipe contains:
- name;
- description;
- style/recommendation text, e.g. "ideal for street photography";
- target camera model;
- optional lens as free text;
- one or more predefined categories;
- free-form tags;
- author;
- creation/publication timestamps;
- recipe settings;
- at least one example image.

## 6. Categories

MVP categories are multi-select:
- Street
- Portrait
- Landscape
- Travel
- Architecture
- Nature
- Wildlife
- Automotive
- Night
- Low Light
- Golden Hour
- Black & White
- Cinematic
- Vintage
- Everyday
- Indoor
- Food
- Documentary

Free-form tags exist in addition to categories.

## 7. Example images and storage

- Minimum: 1 image per recipe.
- Maximum: 5 images per recipe.
- Maximum original image size: 25 MB per image.
- Maximum backend image storage quota: 5 GB per user.
- Original uploaded images are retained in object storage.
- The backend may generate optimized thumbnails/derivatives for feeds and detail screens.
- Saved recipes and suitable image representations are cached locally for offline usage.

The backend uses an S3-compatible object-storage abstraction. Storage-provider-specific behavior must not leak into the iOS domain layer.

## 8. Fujifilm X-S20 recipe settings

The capability model must support at minimum the X-S20 settings relevant to film-simulation recipes, including:
- Film Simulation
- Dynamic Range
- Grain Effect
- Color Chrome Effect
- Color Chrome FX Blue
- White Balance
- White Balance Shift
- Highlight Tone
- Shadow Tone
- Color
- Sharpness
- High ISO Noise Reduction
- Clarity
- ISO
- Exposure Compensation recommendation

Settings are represented through a camera-capability model so future cameras can expose different settings, supported values, ranges, and custom-slot behavior.

## 9. Camera transfer

The MVP target flow is:
1. Connect iPhone and Fujifilm X-S20 via USB-C.
2. Detect and identify the camera.
3. Determine available custom-setting slots.
4. Select a recipe.
5. Select target custom slot, initially C1-C4 as required by supported X-S20 behavior discovered during implementation.
6. Warn before overwriting an occupied slot.
7. Transfer supported settings.
8. Verify transfer when technically possible and report a clear result.

Camera communication must be encapsulated behind a `CameraService`/adapter boundary so protocol-specific implementation can change without affecting recipe UI or persistence.

A technical research spike is mandatory before production implementation of camera communication.

## 10. Community discovery

The MVP contains:
- Popular feed
- New feed
- Search
- Filters
- Recipe detail
- Public user profiles
- Likes
- Views
- Downloads/copies

Comments and follows are not part of the MVP.

### Popularity
Store at least:
- `views_count`
- `likes_count`
- `downloads_count`

Popularity is computed from these signals. The formula must be replaceable without a schema migration.

## 11. Offline behavior

Offline-capable:
- personal recipe library;
- locally saved recipe details;
- cached images;
- local search/browse of saved recipes;
- camera transfer for locally available recipes.

Online-only:
- community browsing beyond cached content;
- authentication refresh when required;
- likes;
- publication;
- downloading/copying new recipes;
- profile synchronization.

SwiftData is used for local metadata/persistence. Images use an application-managed local file cache.

## 12. Backend

Backend stack:
- Laravel REST API
- PostgreSQL
- Redis for cache and queues
- S3-compatible object storage for recipe images
- Docker Compose (`docker/docker-compose.yml`)
- Coolify deployment

`docker/docker-compose.yml` is the canonical Compose definition. It should contain:
- API/web service
- queue worker
- scheduler
- PostgreSQL
- Redis

Secrets must be provided as runtime environment variables, especially in Coolify.

## 13. API design principles

- Versioned API under `/api/v1`.
- JSON only for application APIs.
- Stable identifiers; prefer UUID/ULID over sequential IDs for externally exposed resources.
- Consistent validation error format.
- Cursor or appropriate pagination for community feeds.
- Server-side authorization for every authenticated mutation.
- Idempotent behavior where retries are expected.
- Explicit API resources rather than exposing database models directly.

## 14. iOS architecture

Technology:
- Swift
- SwiftUI
- SwiftData
- Sign in with Apple

Suggested boundaries:
- Features/UI
- Domain models
- API client
- Authentication service
- Recipe repository/service
- Local persistence
- Image cache
- Camera service

The iOS application must not contain backend secrets.

## 15. Core backend domain model

Initial entities:
- User
- CameraModel
- CameraCapability
- Recipe
- RecipeSetting
- RecipeImage
- Category
- Tag
- Like
- RecipeCopy/Provenance
- RecipeView

Exact normalization may evolve during implementation, but camera capabilities and recipe provenance must remain first-class concepts.

## 16. Non-functional requirements

- Tests for critical backend and iOS domain behavior.
- CI for backend, iOS, and Docker builds.
- No credentials or signing secrets committed to Git.
- Public image endpoints must not expose private recipes.
- Upload limits and per-user quotas are enforced server-side.
- API authorization must never rely solely on client-side state.
- Accessible SwiftUI controls and Dynamic Type should be considered in MVP UI.

## 17. Out of MVP / backlog

- Additional Fujifilm camera models
- Comments
- Follow system
- Content reporting
- Admin moderation
- Creator monetization
- Subscription or in-app purchases
- Advanced notifications
- Curated collections
- Advanced trending/recommendation algorithms
- Android client

## 18. MVP completion criteria

The MVP is complete when an anonymous user can discover compatible recipes, an authenticated user can create a private recipe with example images, publish an immutable public recipe, copy another user's recipe into the personal offline library, and transfer a locally available compatible recipe from an iPhone to a connected Fujifilm X-S20 custom-setting slot over USB-C.
