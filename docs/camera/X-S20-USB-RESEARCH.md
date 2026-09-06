# Fujifilm X-S20 USB/PTP research record

Status: implementation guidance recorded; real-device vendor-property
verification remains required before camera writes are enabled.

## Decision

Use Apple `ImageCaptureCore` as the iOS transport boundary. The application
uses `ICDeviceBrowser` and `ICCameraDevice`, checks the camera's PTP capability,
opens an explicit session, sends PTP commands through
`requestSendPTPCommand`, validates responses, and closes the session on every
exit path.

`ExternalAccessory` is not selected because the documented X-S20 USB workflow
uses USB computer modes and FUJIFILM X Acquire rather than an MFi accessory
protocol.

Evidence:

- [Apple ImageCaptureCore](https://developer.apple.com/documentation/imagecapturecore/)
- [Apple ICCameraDevice](https://developer.apple.com/documentation/imagecapturecore/iccameradevice)
- [Apple PTP command API](https://developer.apple.com/documentation/imagecapturecore/iccameradevice/requestsendptpcommand%28_%3Aoutdata%3Acompletion%3A%29)
- [X-S20 Network/USB Setting Menus](https://fujifilm-dsc.com/en/manual/x-s20/connections/network_usb_menu/)
- [X-S20 Saving and Loading Settings](https://fujifilm-dsc.com/en/manual/x-s20/connections/save_load_setting/)

## Confirmed from Fujifilm documentation

The X-S20 documents `USB RAW CONV./BACKUP RESTORE` as the USB connection mode
for saving and loading camera settings with FUJIFILM X Acquire. It documents
`AUTO` and `POWER SUPPLY OFF/COMM ON` as USB power/communication settings and
requires a data-capable USB connection for communication.

The documentation does not publish a third-party API for editing individual
custom-setting slots. Therefore the application must not treat the documented
backup/restore workflow as evidence that recipe-level PTP writes are safe.

## Protocol map

The following standard PTP operation codes are protocol primitives, not proof
that the X-S20 accepts every operation through iOS:

| Operation | Code | Use |
| --- | ---: | --- |
| `GetDeviceInfo` | `0x1001` | Identify the device and enumerate supported operations |
| `OpenSession` | `0x1002` | Start a PTP session |
| `GetDevicePropDesc` | `0x1014` | Read property metadata when supported |
| `GetDevicePropValue` | `0x1015` | Read a property |
| `SetDevicePropValue` | `0x1016` | Candidate write operation; hardware validation required |

Community Fujifilm protocol notes describe provisional vendor properties for
slot selection and image-quality values, including `0xD18C` as a candidate
custom-slot selector. Those codes are retained only as test hypotheses. They
are not enabled as X-S20 write mappings because the referenced hardware was not
an X-S20 validation device.

## Read-only implementation boundary

The current `ImageCaptureCameraService` safely supports:

1. USB camera discovery and X-S20 candidate matching.
2. PTP capability and session checks.
3. Device-info reads and response validation.
4. Reading the currently selected slot and its requested properties.
5. Explicit errors for unsupported devices, malformed responses, and
   transaction mismatches.

It does not automatically select C1-C4, write a slot selector, encode recipe
values, or report a successful recipe transfer. This is intentional until the
hardware plan below is completed.

## Hardware validation plan

Record the camera firmware, iPhone/iOS version, cable, USB mode, device
identifiers, and each raw response. Then:

1. Configure `USB RAW CONV./BACKUP RESTORE` and `POWER SUPPLY OFF/COMM ON`.
2. Verify discovery, session open, `GetDeviceInfo`, and clean session close.
3. Read the supported-property list and C1-C4 without changing the camera.
4. Compare decoded values with the camera UI and FUJIFILM X Acquire backup.
5. Back up the original settings before any write experiment.
6. Test one sacrificial slot/property, read it back, and record the result.
7. Test invalid values, disconnects, partial writes, and rollback.
8. Restore the original settings and verify restoration on the camera.

No write should be enabled from a successful PTP response alone. A transfer
success requires confirmed application of the value and read-back evidence.

## Go/no-go recommendation

Go for the `ImageCaptureCore` read-only prototype and transport-independent
service tests. No-go for production recipe writes until an X-S20 has verified
property support, value encodings, slot behavior, and rollback behavior. ISO
and exposure-compensation recommendation mappings are also unresolved and
must remain local-only until independently verified.

The longer research notes and source links remain in
`docs/CAMERA_USB_PTP_RESEARCH.md`.
