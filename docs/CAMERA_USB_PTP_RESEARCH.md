# Fujifilm X-S20 USB/PTP research

Status: research spike completed 2026-09-05

## Decision

Prototype the camera path with Apple's `ImageCaptureCore` framework on iOS.
`ICDeviceBrowser` can discover camera devices and `ICCameraDevice` exposes an
asynchronous `requestSendPTPCommand` API for PTP commands. Apple documents that
PTP cameras expose the `cameraDeviceCanAcceptPTPCommands` capability.

This keeps USB transport behind the existing `CameraService` boundary and
avoids requiring an MFi accessory protocol. `ExternalAccessory` is intended
for MFi accessories and requires a manufacturer-provided accessory protocol;
that is not the interface documented by Fujifilm for this camera.

Do not use `requestSendMessage` for this path. Apple's documentation explicitly
directs PTP clients to `requestSendPTPCommand` instead.

## What Fujifilm documents

The X-S20 has a USB Type-C USB 10 Gbps connector. Its connection modes include:

- `USB CARD READER` for transferring images;
- `USB TETHER SHOOTING AUTO/FIXED` for remote shooting;
- `USB RAW CONV./BACKUP RESTORE` for computer-based settings backup and restore.

For settings transfer, the camera should be tested in
`USB RAW CONV./BACKUP RESTORE` with `USB POWER SUPPLY/COMM SETTING` set to
`POWER SUPPLY OFF/COMM ON` or `AUTO`. Fujifilm documents the backup/restore
workflow with X Acquire, but does not publish a third-party recipe-slot API.

The manual also says to use a data-capable cable, connect directly without a
hub, and turn the camera off before disconnecting. These should become setup
guidance and teardown behavior in the iOS flow.

Sources:

- [X-S20 Network/USB Setting Menus](https://fujifilm-dsc.com/en/manual/x-s20/connections/network_usb_menu/)
- [X-S20 Saving and Loading Settings](https://fujifilm-dsc.com/en/manual/x-s20/connections/save_load_setting/)
- [X-S20 Connecting to Smartphones (USB)](https://fujifilm-dsc.com/en/manual/x-s20/connections/usage_usb/)
- [X-S20 specifications](https://fujifilm-dsc.com/en/manual/x-s20/technical_notes/spec/)

## iOS transport findings

`ImageCaptureCore` is the preferred first implementation:

1. Create an `ICDeviceBrowser` and observe camera additions/removals.
2. Select an `ICCameraDevice` whose manufacturer/model match Fujifilm/X-S20.
3. Check `usbVendorID`, `usbProductID`, transport type, and
   `cameraDeviceCanAcceptPTPCommands`; do not identify the camera by display
   name alone.
4. Request an open session.
5. Send PTP commands with `requestSendPTPCommand(_:outData:completion:)`.
6. Treat the returned response and data as untrusted input and validate the
   response code, transaction id, payload length, and property values.
7. Close the session and release application state on both normal and failure
   paths.

Apple also documents `ptpEventHandler` on `ICCameraDevice`, which can be used
later for asynchronous camera events. It is not required for the initial
read-only proof of concept.

Sources:

- [Apple ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore/)
- [Apple ICCameraDevice](https://developer.apple.com/documentation/imagecapturecore/iccameradevice)
- [Apple requestSendPTPCommand](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand%28_%3Aoutdata%3Acompletion%3A%29)
- [Apple External Accessory](https://developer.apple.com/documentation/externalaccessory)

## Fujifilm PTP protocol hypothesis

The following is a useful implementation hypothesis, not X-S20 acceptance
evidence. Independent community implementations report standard PTP operations
and Fujifilm vendor properties for X-H2 and X-T5 hardware:

| Operation or property | Value | Intended use |
|---|---:|---|
| `OpenSession` | `0x1002` | Start a PTP session |
| `GetDeviceInfo` | `0x1001` | Identify device and enumerate supported properties |
| `GetDevicePropDesc` | `0x1014` | Read property type and legal values |
| `GetDevicePropValue` | `0x1015` | Read a property |
| `SetDevicePropValue` | `0x1016` | Write a property |
| Fujifilm slot selector | `0xD18C` | Select C1, C2, etc. |
| Fujifilm preset name | `0xD18D` | Read/write the selected slot name |
| Fujifilm recipe block | `0xD18E..0xD1A4` | Read/write slot properties |
| Dynamic Range | `0xD190` | Stored recipe property |
| Film Simulation | `0xD192` | Stored recipe property |
| Grain Effect | `0xD195` | Stored recipe property |
| Color Chrome / FX Blue | `0xD196` / `0xD197` | Stored recipe properties |
| White Balance / WB shift | `0xD199` / `0xD19A..0xD19B` | Stored recipe properties |
| Tone / Color / Sharpness | `0xD19D..0xD1A0` | Stored recipe properties |
| High ISO NR / Clarity | `0xD1A1` / `0xD1A2` | Stored recipe properties |

The reference material reports little-endian PTP values, a slot selector before
slot reads/writes, and read-back verification after writes. It also reports
that property support and encodings vary by camera generation. The X-S20 is
not listed as a hardware-tested body in that material; therefore these values
must remain provisional until verified on the actual target camera.

Reference material:

- [Community Fujifilm PTP protocol notes](https://github.com/ILFforever/fujifilm-ptp-recipes/blob/main/docs/protocol.md)
- [Community recipe property notes](https://github.com/ILFforever/fujifilm-ptp-recipes/blob/main/docs/properties.md)
- [libgphoto2 Fujifilm PTP implementation](https://github.com/gphoto/libgphoto2/blob/master/camlibs/ptp2/ptp.c)

### Important capability gap

The reference slot-property map covers the image-quality recipe controls but
does not establish a slot-write mapping for the MVP's ISO and exposure
compensation recommendation fields. These must not be silently written using
guessed property codes. Until tested, the adapter should report them as
unsupported for camera transfer while retaining them in the local recipe.

## Hardware validation plan

The following sequence is required before enabling writes:

1. Use an X-S20 with documented firmware version, a charged battery, and a
   short data-capable USB-C cable connected directly to the iPhone.
2. Record the device VID/PID, USB interfaces, endpoints, camera model, and
   firmware version from the `ICCameraDevice` and diagnostic logs. Never log
   credentials or unrelated camera data.
3. Set `USB RAW CONV./BACKUP RESTORE` and `POWER SUPPLY OFF/COMM ON` on the
   camera.
4. Prove discovery, session open, `GetDeviceInfo`, and clean session close.
5. Confirm whether the supported-property list contains `0xD18C`.
6. Read C1-C4 only. Save raw responses locally as test artifacts and compare
   decoded values with the camera UI.
7. Back up the original camera settings before any write test.
8. Write one harmless name or one sacrificial slot property, then read it back.
9. Test each supported recipe property independently, including invalid values,
   dependency cases such as Dynamic Range Priority, and cable/power loss.
10. Restore the original slot and verify restoration from the camera.

The read-only steps belong in issue #8/#9. Single-property write and verified
rollback belong in issue #10. A successful PTP response alone is not proof that
the camera applied the requested setting.

## Outcome for the roadmap

- Feasible iOS transport: `ImageCaptureCore` PTP commands.
- Not yet proven: X-S20 vendor-property support and value encodings.
- Not yet proven: whether all four X-S20 custom banks expose the expected
  property block.
- Explicitly deferred: ISO and exposure-compensation slot mappings.
- Next implementation: a read-only iOS camera discovery/session prototype with
  diagnostics and no write operations.
