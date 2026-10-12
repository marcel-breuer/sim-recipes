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

Recipe detail and the personal library can create an offline PNG share card
from a recipe photo or a photo-library selection. Cards support dark/editorial
layouts, crop focus, and summary/all-settings variants. Public cards include the
stable public recipe link; private cards omit recipe and image URLs. A card is a
visual snapshot for sharing, distinct from the versioned `.simrecipe` file used
for recipe import/export and the public deep link used to open the canonical
recipe.

The recipe editor can scan a saved or newly captured recipe photo into a
private, editable draft using on-device Vision text recognition. The source
image is held only for extraction and is not attached or uploaded. Recognized
settings show their source text and confidence, are matched against the selected
camera's capability list, and require review before applying. Unknown,
unsupported, low-confidence, and duplicate fields are flagged instead of
guessed. Scanning never saves, publishes, or transfers a recipe; verify the
draft against the source before continuing.

The JPEG darkroom opens photo-library or local JPEG files for on-device
non-destructive edits. Projects retain the original in the app's private local
support directory and persist reversible recipe, light/color, crop, straighten,
and frame parameters. Selected adjustment groups can be synchronized across a
batch. Export creates a separate JPEG; source metadata and GPS are removed by
default, with an explicit option to preserve them in the exported copy.

Do not place credentials or signing material in this directory.
