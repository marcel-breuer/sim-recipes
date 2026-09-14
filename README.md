# SimRecipes

SimRecipes is an iOS application for creating, discovering, sharing, saving, and transferring Fujifilm film-simulation recipes.

The MVP targets the Fujifilm X-S20 and iPhone. Users can browse public recipes anonymously, sign in with Apple to create or save recipes, keep private recipes, publish immutable community recipes, and transfer compatible recipe settings to camera custom-setting slots over USB-C.

## MVP stack

- iOS: Swift, SwiftUI, SwiftData
- Authentication: Sign in with Apple
- Backend: Laravel REST API
- Database: PostgreSQL
- Cache and queues: Redis
- Image storage: Laravel local filesystem on a persistent Docker volume
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
├── docker/
│   ├── docker-compose.yml
│   ├── Dockerfile
│   └── .env.example
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

The Laravel service also serves the public product landing page at `/`. The
application API remains versioned under `/api/v1`; the landing page is a
separate public presentation surface and does not expose repository links.

## Repository status

Private repository. No open-source license is granted.

See `PROJECT_SPEC.md` for the MVP specification, `docker/README.md` for local
and Coolify deployment, and `AGENTS.md` for engineering conventions.
Release-candidate checks and known limitations are tracked in
`docs/RELEASE_VALIDATION.md`.

## Example photography

The public landing page uses the approved example photograph
[`example-street.jpg`](backend/public/images/example-street.jpg), also shown
in the product preview above. It is original SimRecipes artwork, cleared for
use and modification in this repository and its landing page; it contains no
third-party logos, identifiable people, or location metadata. The asset is
stored as an optimized JPEG derivative rather than an unnecessary original.

![A quiet stone street at blue hour with warm window light](backend/public/images/example-street.jpg)

See [`docs/EXAMPLE_PHOTOS.md`](docs/EXAMPLE_PHOTOS.md) for the source, rights,
alt text, and validation record.
