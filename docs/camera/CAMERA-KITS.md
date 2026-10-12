# Camera kit installation

Camera kits use recipes already present in the local library, so saved recipes
remain available offline. Every recipe must be mapped explicitly to a
different C1-C4 slot, and the app checks the camera capability catalog before
offering a transfer. The most recent capability catalog is cached locally for
offline preflight.

The current USB adapter cannot select camera slots or encode X-S20 recipe
values. Slot contents other than the currently selected slot are therefore
reported as unknown, and every mapped slot requires an explicit overwrite
confirmation. The app verifies the selected slot before attempting a write,
reports only read-back-confirmed success, and reports unsupported encoding as
a failed attempt with no write issued. A transfer error after a mutation may
have started is reported as unknown.

This is the guarded kit-planning and execution workflow for issue #132; it does
not establish camera-write support. Enable successful installation only after
the hardware validation in [X-S20 USB/PTP research](X-S20-USB-RESEARCH.md)
confirms property values, slot behavior, and recovery on a real camera.
