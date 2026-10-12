# Wireless Fujifilm camera workflows

Research status: documentation review completed 2026-10-12. No Fujifilm camera
was connected for hardware validation, and Xcode command-line developer tools
were unavailable in the research environment. Camera-specific protocol support
and firmware behavior below are therefore not represented as hardware-tested.

## Capability matrix

| Camera / firmware | Bluetooth pairing | Recipe-slot read/write | Wireless photo import | Evidence status |
| --- | --- | --- | --- | --- |
| Fujifilm X-S20 / firmware not recorded | Documented by Fujifilm for smartphone pairing and camera features | No public recipe-slot protocol found in the reviewed Fujifilm documentation | Fujifilm documents smartphone image transfer; image transfer uses a wireless LAN connection after pairing | Vendor features documented; third-party protocol and SimRecipes operation unverified |
| Other models / firmware not evaluated | Unknown | Unknown | Unknown | Untested; do not infer support from the X-S20 or another app |

The camera's own manual describes selecting images for transfer to a paired
smartphone and notes that the camera switches to wireless LAN when copying
pictures. This documents a Fujifilm smartphone workflow, not a public protocol
that third-party apps can rely on. The reviewed material does not document a
Bluetooth command/API for reading or writing custom recipe slots.

## iOS feasibility and privacy constraints

- Core Bluetooth provides iOS APIs for Bluetooth Low Energy and BR/EDR devices.
  Framework availability does not establish that the camera exposes a usable
  third-party recipe service, its protocol, or permission to write camera slots.
- A local-network photo-transfer implementation must account for iOS local
  network permission. Apple requires an explanatory `NSLocalNetworkUsageDescription`
  when an app accesses the local network; Bonjour browsing also requires the
  appropriate service declarations. The exact networking path cannot be chosen
  until the camera endpoint and protocol are observed.
- Pairing and transfer must be user initiated, show the camera and connection
  state, and explain required permissions. Never assume background transfer,
  silently pair, or upload imported images to SimRecipes' backend.
- A recipe write must use the existing capability checks and explicit
  occupied-slot confirmation. Report each operation as verified, failed, or
  unknown; a transport acknowledgement alone is not proof that a setting was
  applied. Keep raw camera responses and personal image metadata out of logs.
- If a multi-file or multi-slot operation is interrupted, preserve completed
  results and report the remaining work. Do not claim an all-or-nothing result
  unless the camera protocol provides a tested transaction/rollback guarantee.

## Comparison with the existing USB path

The existing [X-S20 USB/PTP research](X-S20-USB-RESEARCH.md) establishes a
read-only `ImageCaptureCore` prototype boundary and documents the X-S20 USB
connection modes. It also states that Fujifilm documents whole-camera settings
backup/restore with X Acquire, but does not publish a third-party API for
editing individual recipe slots. The existing USB research and implementation
must remain unchanged by this wireless assessment.

Wireless import may be a useful second transport for photos, but it should not
be coupled to Bluetooth recipe control. They have different documented
behaviors and need independent compatibility results and failure handling.

## Go / no-go

| Workflow | Decision | Reason / next evidence needed |
| --- | --- | --- |
| Bluetooth read/write of custom recipe slots | **No-go for implementation** | No public slot protocol was identified and no camera was available. Reconsider only after an X-S20 and each proposed model/firmware can be paired and slot reads/writes can be captured and verified. |
| Wireless photo import | **No-go for implementation; retain as a candidate** | Fujifilm documents image transfer through its smartphone workflow, but this review did not establish a supported third-party transport, file endpoint, or authentication flow. Inspect a real X-S20 session and validate transfer, file types, reconnect, and permission behavior before building an adapter. |
| Existing USB/PTP recipe workflow | **No change** | Continue under [X-S20 USB/PTP research](X-S20-USB-RESEARCH.md); wireless documentation is not evidence for USB recipe writes. |

No follow-up implementation should claim X-S20 Bluetooth recipe support or
third-party wireless photo import until that evidence exists. Update the matrix
with model, firmware, iOS version, test setup, steps, and observed results when
hardware becomes available.

## Sources

- [FUJIFILM X-S20: Connecting to Smartphones (Bluetooth)](https://fujifilm-dsc.com/en-int/manual/x-s20/connections/usage_smartphone_app/)
- [FUJIFILM X-S20: Network/USB Setting Menus](https://fujifilm-dsc.com/en/manual/x-s20/connections/network_usb_menu/)
- [FUJIFILM X-S20: Overview of network and USB features](https://app.fujifilm-dsc.com/en-int/manual/x-s20/connections/overview/)
- [Apple Core Bluetooth](https://developer.apple.com/documentation/corebluetooth)
- [Apple TN3179: Understanding local network privacy](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- [Apple `NSLocalNetworkUsageDescription`](https://developer.apple.com/documentation/bundleresources/information-property-list/nslocalnetworkusagedescription)
- [Fuji Recipes App Store listing](https://apps.apple.com/de/app/fuji-recipes-film-simulation/id6761905712) (competitor feature context only)
