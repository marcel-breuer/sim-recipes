# SimRecipes iOS client

The iOS client is a SwiftUI application targeting iOS 17 and later. The shared
`SimRecipes` scheme builds the app and its unit-test target on an iPhone
Simulator.

The current shell contains the Explore, Library, and Profile product sections.
The read-only camera prototype uses an ImageCaptureCore service boundary for
USB camera discovery, X-S20 candidate matching, session management, and a
validated `GetDeviceInfo` PTP request. It does not write camera settings.
Networking, SwiftData persistence, image caching, and authentication remain
behind service boundaries and will be added in their respective implementation
issues.

Do not place credentials or signing material in this directory.
