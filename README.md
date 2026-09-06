# SimRecipes

SimRecipes is an iOS application for creating, discovering, sharing, saving, and transferring Fujifilm film-simulation recipes.

The MVP targets the Fujifilm X-S20 and iPhone. Users can browse public recipes anonymously, sign in with Apple to create or save recipes, keep private recipes, publish immutable community recipes, and transfer compatible recipe settings to camera custom-setting slots over USB-C.

## MVP stack

- iOS: Swift, SwiftUI, SwiftData
- Authentication: Sign in with Apple
- Backend: Laravel REST API
- Database: PostgreSQL
- Cache and queues: Redis
- Image storage: S3-compatible object storage
- Deployment: Docker Compose on Coolify
- Initial camera: Fujifilm X-S20

## Repository structure

The implementation will use a monorepo structure:

```text
/
├── ios/
├── backend/
├── docker/
├── docs/
├── docker-compose.yml
├── AGENTS.md
├── PROJECT_SPEC.md
└── README.md
```

## Product principles

- Public recipes are immutable after publication.
- Changes to published recipes create a copy rather than modifying the original.
- Community downloads create an account-owned copy in the same personal recipe library.
- Private recipes remain editable and deletable until publication.
- Camera compatibility is capability-driven rather than hard-coded into UI flows.
- Saved recipes and cached images must remain usable offline.
- Camera transfer must work offline after a recipe is available locally.
- The backend is the source of truth for public/community data; SwiftData is the offline/local persistence layer.

## Repository status

Private repository. No open-source license is granted.

See `PROJECT_SPEC.md` for the MVP specification and `AGENTS.md` for engineering conventions.
Release-candidate checks and known limitations are tracked in
`docs/RELEASE_VALIDATION.md`.
