# SimRecipes Implementation Roadmap

This roadmap defines the recommended implementation order. GitHub issue numbers are the source of truth for acceptance criteria.

## Phase 0 — Foundation

1. #1 Bootstrap repository structure and engineering conventions
2. #2 Set up GitHub Actions quality gates
3. #3 Create Laravel API foundation
4. #4 Create production Docker Compose stack for Coolify
5. #5 Design and implement core database schema

Outcome: backend, CI, PostgreSQL, Redis, and deployment foundation are ready.

## Phase 1 — Camera risk reduction and domain model

Run this phase early and in parallel with application scaffolding.

1. #6 Implement camera capability model and seed Fujifilm X-S20
2. #7 Research Fujifilm X-S20 USB-C/PTP camera communication
3. #11 Create SwiftUI iOS application foundation
4. #8 Prototype X-S20 detection and camera session on iOS
5. #9 Read X-S20 custom-setting slots
6. #10 Write and verify recipes in X-S20 custom-setting slots

Outcome: the highest-risk technical assumption—direct camera transfer—is proven before extensive product UI is built.

## Phase 2 — Data, authentication, and account layer

1. #12 Implement API client, SwiftData persistence, and offline sync foundation
2. #13 Implement Sign in with Apple and backend authentication
3. #14 Implement user profiles

Outcome: anonymous browsing and authenticated mutations have stable technical foundations.

## Phase 3 — Recipe core

1. #15 Implement recipe creation, private lifecycle, and immutable publishing API
2. #16 Implement recipe image storage, derivatives, and user quota
3. #17 Implement recipe editor and publishing flow on iOS

Outcome: users can create private recipes with images and publish immutable public recipes.

## Phase 4 — Community and personal library

1. #18 Implement community feeds, search, and filters
2. #19 Implement likes, views, downloads, and popularity ranking
3. #20 Implement recipe copy/download and provenance
4. #21 Implement personal recipe library and offline image cache
5. #22 Implement recipe detail and community actions on iOS

Outcome: discovery, ranking, sharing/copying, and offline personal storage are complete.

## Phase 5 — Camera product integration

1. #23 Implement camera connection, slot selection, and transfer UI

Outcome: the proven X-S20 transport implementation is integrated into the user-facing product flow and works offline.

## Phase 6 — Functional MVP validation

1. #29 Run end-to-end MVP hardening and release-candidate validation

Outcome: the functional MVP meets the product completion criteria in `PROJECT_SPEC.md`.

## Public App Store release gate

Before public App Store submission:

1. #24 Add App Store UGC safety and moderation requirements

This is deliberately outside the functional MVP but is a release dependency because SimRecipes contains user-generated public content. Apple's requirements must be re-verified immediately before implementation/submission.

## Post-MVP backlog

- #25 Add support for additional Fujifilm camera models
- #26 Add recipe comments
- #27 Add creator follow system
- #28 Design and implement monetization

## Recommended parallel work

After Phase 0, the following tracks can proceed concurrently:

```text
Camera track:     #6 → #7 → #8 → #9 → #10 → #23
Backend track:    #5 → #13 → #15 → #16 → #18 → #19 → #20
iOS/data track:   #11 → #12 → #13 → #17 → #21 → #22 → #23
```

Avoid delaying #7 until late in the project. Direct X-S20 transfer is the highest technical dependency in the MVP and should be proven before the community UI becomes the dominant implementation effort.