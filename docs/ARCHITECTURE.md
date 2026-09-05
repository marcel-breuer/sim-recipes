# SimRecipes Architecture

## System context

```text
┌───────────────────────────────┐
│ iPhone / SimRecipes iOS       │
│ SwiftUI + SwiftData           │
│                               │
│ Explore / Library / Create    │
│ Auth / Offline / Camera       │
└───────────────┬───────────────┘
                │ HTTPS / JSON
                ▼
┌───────────────────────────────┐
│ Laravel REST API              │
│ /api/v1                       │
└───────┬────────┬──────────────┘
        │        │
        │        └───────────────► S3-compatible object storage
        │                         original recipe images + derivatives
        │
        ├────────► PostgreSQL
        │         durable application data
        │
        └────────► Redis
                  cache + queue

Docker/Coolify runtime:
api + queue + scheduler + postgres + redis

Separate device path:

iPhone ── USB-C ──► Fujifilm X-S20
                    custom-setting slots
```

## iOS layers

### UI/features
Primary MVP features:
- Explore
- Search and filters
- Recipe detail
- Personal library
- Recipe creation
- Profile
- Authentication
- Camera connection and transfer

### Domain/services
Suggested boundaries:
- `APIClient`: HTTP transport and API contract handling
- `AuthService`: Sign in with Apple and backend session/token lifecycle
- `RecipeRepository`: unified access to remote and local recipes
- `LocalRecipeStore`: SwiftData persistence
- `ImageCache`: durable local recipe-image cache
- `CameraService`: camera discovery, capabilities, slots, transfer, verification

### Offline model
The personal library is locally persisted. Network synchronization updates server-owned/community data when connectivity is available. Camera transfer operates on a fully local recipe representation and therefore does not require network access.

## Backend components

### API
Laravel exposes a versioned JSON API. Controllers should remain thin and delegate domain/state transitions to dedicated application services/actions.

### PostgreSQL
Stores users, profiles, camera models/capabilities, recipes/settings, categories/tags, image metadata, provenance, likes, views, and download/copy events.

### Redis
Used for queues and cache. Counters may use Redis as an optimization, but PostgreSQL remains the durable source where required.

### Queue
Processes asynchronous work such as image derivatives and future notifications/maintenance tasks.

### Scheduler
Runs Laravel scheduled tasks such as aggregation, cleanup, or future maintenance jobs.

### Object storage
Stores original recipe example images and generated derivatives through Laravel's filesystem abstraction.

## Core domain boundaries

### Recipe aggregate
A recipe owns its settings, selected categories, tags, image metadata, target camera model, visibility, lifecycle state, and provenance.

Private recipes are mutable. Publication freezes the published recipe. Subsequent changes require duplication.

### Camera capability model
Camera support must be data/capability driven. A camera model defines:
- supported recipe settings;
- allowed values/ranges;
- transport-relevant identifiers discovered through implementation research;
- supported custom-slot behavior.

The UI should render valid controls from these capabilities rather than assume every Fujifilm camera has the same settings.

### Provenance
Copies retain a reference to the source recipe and author where available. A copied recipe becomes independently owned; changes never mutate the source.

## Camera communication architecture

```text
Recipe
  │
  ▼
Compatibility Validator
  │
  ▼
CameraService protocol
  │
  ├── Camera discovery
  ├── Device identification
  ├── Read capabilities / slots
  ├── Encode recipe settings
  ├── Write selected slot
  └── Verify result
       │
       ▼
Fujifilm X-S20 transport adapter
       │
       ▼
USB-C / protocol implementation
```

The transport adapter is intentionally isolated because the available Fujifilm USB/PTP behavior must be researched and validated on real hardware.

The initial iOS transport choice is Apple's `ImageCaptureCore` framework:
`ICDeviceBrowser`/`ICCameraDevice` handles camera discovery and sessions, while
the Fujifilm adapter sends PTP commands through `requestSendPTPCommand`. The
adapter must still verify the X-S20 model, supported property list, response
codes, and read-back values before reporting a transfer as successful. See
`docs/CAMERA_USB_PTP_RESEARCH.md` for the research record and hardware test
plan.

The iOS transfer flow is local-first: it reads a saved recipe, discovers a
connected X-S20, loads the slots reported by `CameraService`, requires an
explicit overwrite confirmation, and exposes progress and retry/exit states.
The UI only enters its success state after the adapter returns a verified
snapshot. The current adapter intentionally reports recipe-transfer encoding
as unavailable until the provisional X-S20 property encodings are validated on
hardware; it therefore cannot claim a write or silently change camera values.

## Deployment

One root-level `docker-compose.yml` is the deployment definition.

Expected services:
- `api`
- `queue`
- `scheduler`
- `postgres`
- `redis`

Only the API service is publicly routable in Coolify. PostgreSQL and Redis remain internal. Persistent data uses Docker/Coolify volumes. Object images live outside the Compose stack in S3-compatible storage.

## API evolution

The initial public application contract is `/api/v1`. Within v1, changes should remain backward compatible where feasible. Breaking changes require deliberate versioning and coordinated iOS migration.

## Key architectural risks

1. Fujifilm X-S20 USB-C protocol access from iOS.
2. Reliable write and verification behavior for custom-setting slots.
3. Correct mapping between human-readable recipe values and protocol values.
4. Offline synchronization and provenance consistency.
5. Original image storage costs and per-user quota enforcement.
6. Apple authentication/session lifecycle.

Camera communication research is therefore an early implementation priority rather than a late integration task.
