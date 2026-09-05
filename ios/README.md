# SimRecipes iOS client

The iOS client is a SwiftUI application targeting iOS 17 and later. The shared
`SimRecipes` scheme builds the app and its unit-test target on an iPhone
Simulator.

The current shell contains the Explore, Library, and Profile product sections.
The read-only camera prototype uses an ImageCaptureCore service boundary for
USB camera discovery, X-S20 candidate matching, session management, a
validated `GetDeviceInfo` PTP request, and capability-driven property reads for
the camera-selected custom slot. It does not write camera settings or change
the selected slot. The write path requires explicit slot confirmation, a
supported property set, validated raw PTP payloads, per-property read-back,
and rollback on failure; it never writes the slot selector automatically.
Networking, SwiftData persistence, image caching, and authentication remain
behind service boundaries and will be added in their respective implementation
issues.

Do not place credentials or signing material in this directory.
