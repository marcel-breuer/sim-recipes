# Engineering Conventions

These rules apply to all contributors and automated coding agents working in this repository.

## 1. General principles

- Read `README.md`, `PROJECT_SPEC.md`, and relevant documentation before changing code.
- Work from a GitHub issue with explicit acceptance criteria.
- Keep changes narrowly scoped to the active issue.
- Prefer simple, testable designs over speculative abstractions.
- Do not silently change product behavior defined in `PROJECT_SPEC.md`.
- If implementation constraints conflict with the specification, document the constraint in the pull request and update the specification only when the product decision is explicit.

## 2. Language

Use English for:
- source code;
- comments;
- documentation;
- GitHub issues;
- branch names;
- commit messages;
- pull-request titles and descriptions.

User-facing application strings may be localized later, but source localization keys and developer-facing descriptions remain in English.

## 3. Git rules

- Default branch: `main`.
- Never commit directly to `main` for implementation work.
- Create one feature/fix branch per GitHub issue.
- Include the issue number in branch names where practical.
- Prefer branch formats such as `feat/12-recipe-editor`, `fix/27-image-cache`, `chore/4-docker-compose`.
- Never include names of AI tools, coding assistants, or model vendors in branch names or commit messages.
- Do not add automated-assistant attribution to commit messages.
- Use Conventional Commits where practical: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`, `ci:`.
- Keep commits coherent and reviewable.
- One issue should normally result in one pull request.
- Reference the issue in the pull request body and close it through the pull request when completed.
- Do not merge a pull request while required CI checks are failing.

## 4. Repository boundaries

Expected structure:

```text
/
├── ios/
├── backend/
├── docker/
├── docs/
├── .github/
├── docker-compose.yml
├── AGENTS.md
├── PROJECT_SPEC.md
└── README.md
```

Do not introduce a second Docker Compose file unless the product owner explicitly changes this decision.

## 5. Backend conventions

- Laravel is an API backend, not a server-rendered application for the MVP.
- PostgreSQL is the primary relational database.
- Redis is used for cache and queues.
- Use Laravel migrations for all schema changes.
- Use Form Requests or equivalent explicit validation boundaries.
- Use policies/gates for authorization instead of controller-only checks.
- Use API Resources/DTO boundaries; do not serialize Eloquent models directly as the public contract.
- Version public application endpoints under `/api/v1`.
- Prefer ULIDs/UUIDs for externally exposed identifiers.
- Keep database transactions around multi-step state changes such as publishing or copying recipes.
- Enforce storage quota, upload limits, ownership, and visibility on the server.
- Avoid N+1 queries in feed/detail endpoints.
- Queue image processing and other expensive non-interactive work.
- Keep object storage behind Laravel's filesystem abstraction.

### Backend quality

Every functional backend change should include appropriate automated tests. Critical flows require feature tests, including:
- authentication/authorization;
- private/public recipe visibility;
- immutable publication behavior;
- recipe copying/provenance;
- image upload limits and quotas;
- likes/views/download accounting;
- camera capability API behavior.

Use Laravel Pint and static analysis (Larastan/PHPStan) once configured.

## 6. iOS conventions

- Use Swift and SwiftUI.
- Use SwiftData for local persistent metadata.
- Prefer Swift concurrency (`async`/`await`) for asynchronous work.
- Keep SwiftUI views declarative and move domain/network/storage behavior out of views.
- Avoid singleton-heavy architecture.
- Use dependency injection at feature/service boundaries.
- Keep API transport models separate from persistent/domain models when their responsibilities differ.
- Treat offline behavior as a first-class requirement, not a later optimization.
- Application secrets must never be embedded in the iOS binary.

### Suggested service boundaries

- `APIClient`
- `AuthService`
- `RecipeRepository`
- `LocalRecipeStore`
- `ImageCache`
- `CameraService`

### Camera integration

- All USB/PTP/Fujifilm-specific behavior must remain behind `CameraService` or protocol-specific adapters.
- Do not couple recipe screens directly to transport/protocol commands.
- Capability-check every setting before transfer.
- Never overwrite a camera custom slot without explicit user confirmation.
- Report partial/failed transfers explicitly; do not claim success without evidence from the protocol or a clearly documented limitation.

## 7. API contract rules

- Treat the API as a contract between separately evolving iOS and backend components.
- Make breaking API changes explicit.
- Prefer additive compatible changes within `/api/v1`.
- Use consistent error objects and HTTP status codes.
- Paginate community feeds.
- Make retries safe for mutation endpoints where feasible.

## 8. Security and privacy

- Never commit `.env` files, Apple private keys, API tokens, storage credentials, Coolify secrets, or signing material.
- Validate all uploads by type and size server-side.
- Private recipe images must never be retrievable through public recipe endpoints.
- Authorize every mutation server-side.
- Minimize personal data stored from Sign in with Apple.
- Do not log credentials, identity tokens, authorization headers, or private image URLs.

## 9. Docker and deployment

- Maintain exactly one root `docker-compose.yml` for the current architecture.
- The target deployment platform is Coolify.
- Expected services are `api`, `queue`, `scheduler`, `postgres`, and `redis`.
- PostgreSQL and Redis must not be exposed publicly in production.
- Use health checks and restart policies.
- Runtime secrets are configured in Coolify, not committed.
- Ensure migrations have a deliberate production startup/deployment strategy.

## 10. Testing expectations

Before a pull request is ready to merge, run all relevant checks for the changed scope.

Backend examples:
- formatter/lint checks;
- static analysis;
- unit and feature tests;
- Docker build validation when infrastructure changes.

iOS examples:
- build for the supported iOS simulator/device target;
- unit tests;
- relevant persistence/service tests;
- UI tests for critical flows when they add meaningful confidence.

## 11. Definition of done

An issue is done only when:
- acceptance criteria are satisfied;
- relevant tests exist and pass;
- CI passes;
- documentation is updated if behavior/configuration changed;
- no secrets or debug artifacts are committed;
- the pull request references the issue;
- the implementation matches `PROJECT_SPEC.md` or documents an explicitly approved specification change.