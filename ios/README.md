# SimRecipes iOS client

The iOS client is a SwiftUI application targeting iOS 17 and later. The shared
`SimRecipes` scheme builds the app and its unit-test target on an iPhone
Simulator.

The current shell contains onboarding plus the Explore, Library, and Profile
product sections. Onboarding stores the preferred supported camera locally and
offers offline-safe photography interest defaults.
The API client, SwiftData recipe metadata store, and repository boundary are
available for offline-first recipe access under `SimRecipes/Data/`.
Sign in with Apple and Keychain-backed session restoration are available under
`SimRecipes/Auth/`; the API base URL is configured through `Info.plist`.
The read-only camera prototype uses an ImageCaptureCore service boundary for
USB camera discovery, X-S20 candidate matching, session management, a
validated `GetDeviceInfo` PTP request, and capability-driven property reads for
the camera-selected custom slot. It does not write camera settings or change
the selected slot. The write path requires explicit slot confirmation, a
supported property set, validated raw PTP payloads, per-property read-back,
and rollback on failure; it never writes the slot selector automatically.
The recipe editor shows an on-device approximate visual preview for selected
example images. It applies only settings advertised by the selected camera's
capability model and provides an accessible before/after comparison; it does
not claim to reproduce Fujifilm color science exactly.
Recipe images are downloaded through the authenticated API client into the
durable `ImageCache`; SwiftData stores their local file URLs with recipe
metadata so the personal library remains useful offline. The recipe editor now loads
camera capabilities and predefined categories from the API, renders supported
settings dynamically, uploads photo-library images as multipart form data, and
stores drafts locally for offline recovery. Published recipes are presented as
immutable and cannot be edited in the editor. Personal collections are cached
locally, can be reordered and edited from Profile, and retain pending recipe
membership changes for synchronization when connectivity returns.

Do not place credentials or signing material in this directory.
