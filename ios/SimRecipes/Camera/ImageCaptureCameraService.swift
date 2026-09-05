import Foundation
import ImageCaptureCore

@MainActor
final class ImageCaptureCameraService: NSObject, CameraService {
    private let browser: ICDeviceBrowser
    private var devicesByID: [String: ICCameraDevice] = [:]
    private var activeCamera: ICCameraDevice?
    private var nextTransactionID: UInt32 = 1

    private(set) var discoveredCameras: [CameraDescriptor] = []

    init(browser: ICDeviceBrowser = ICDeviceBrowser()) {
        self.browser = browser
        super.init()
        browser.delegate = self
        browser.browsedDeviceTypeMask = ICDeviceTypeMask.camera
    }

    func requestControlAuthorization() async throws {
        let status = await withCheckedContinuation { continuation in
            browser.requestControlAuthorization { status in
                continuation.resume(returning: status)
            }
        }

        guard status == .authorized else {
            throw CameraServiceError.authorizationDenied
        }
    }

    func startDiscovery() {
        browser.start()
    }

    func stopDiscovery() {
        browser.stop()
    }

    func openSession(for cameraID: String) async throws {
        guard let camera = devicesByID[cameraID] else {
            throw CameraServiceError.cameraNotFound(cameraID)
        }

        guard let descriptor = discoveredCameras.first(where: { $0.id == cameraID }),
              descriptor.isX20Candidate else {
            throw CameraServiceError.unsupportedCamera
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            camera.requestOpenSession(options: nil) { error in
                Task { @MainActor in
                    if let error = error {
                        continuation.resume(throwing: CameraServiceError.underlying(error))
                    } else if !camera.hasOpenSession {
                        continuation.resume(throwing: CameraServiceError.sessionNotOpen)
                    } else {
                        self.activeCamera = camera
                        self.nextTransactionID = 1
                        continuation.resume()
                    }
                }
            }
        }
    }

    func readDeviceInfo() async throws -> PTPResponseHeader {
        let transaction = try await sendReadOnlyPTPCommand(
            PTPCommand.getDeviceInfo(transactionID: nextTransactionID)
        )
        return transaction.header
    }

    func readProperty(_ propertyCode: UInt16) async throws -> Data {
        let command = PTPCommand.getDevicePropValue(
            propertyCode: propertyCode,
            transactionID: nextTransactionID
        )
        let transaction = try await sendReadOnlyPTPCommand(command)
        return transaction.data
    }

    func readSelectedSlot(_ slot: CameraSlot, propertyCodes: [UInt16]) async throws -> CameraSlotSnapshot {
        let selectedSlotData = try await readProperty(0xD18C)
        guard let selectedSlot = selectedSlotData.cameraSlotValue else {
            throw CameraServiceError.invalidSlotValue
        }

        guard selectedSlot == slot.rawValue else {
            throw CameraServiceError.requestedSlotIsNotSelected(expected: slot, actual: selectedSlot)
        }

        var properties: [UInt16: Data] = [:]
        for propertyCode in propertyCodes {
            properties[propertyCode] = try await readProperty(propertyCode)
        }

        return CameraSlotSnapshot(slot: slot, properties: properties)
    }

    private func sendReadOnlyPTPCommand(_ command: PTPCommand) async throws -> PTPTransaction {
        guard let camera = activeCamera, camera.hasOpenSession else {
            throw CameraServiceError.sessionNotOpen
        }

        guard camera.capabilities.contains(ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue) else {
            throw CameraServiceError.ptpNotSupported
        }

        nextTransactionID = nextTransactionID == .max ? 1 : nextTransactionID + 1

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PTPTransaction, Error>) in
            camera.requestSendPTPCommand(command.encoded, outData: nil) { response, data, error in
                Task { @MainActor in
                    if let error = error {
                        continuation.resume(throwing: CameraServiceError.underlying(error))
                        return
                    }

                    guard let responseHeader = PTPResponseHeader(data: response) else {
                        continuation.resume(throwing: CameraServiceError.invalidPTPResponse)
                        return
                    }

                    guard responseHeader.responseCode == PTPResponseHeader.successResponseCode else {
                        continuation.resume(throwing: CameraServiceError.unexpectedPTPResponseCode(responseHeader.responseCode))
                        return
                    }

                    guard responseHeader.transactionID == command.transactionID else {
                        continuation.resume(throwing: CameraServiceError.transactionMismatch(
                            expected: command.transactionID,
                            actual: responseHeader.transactionID
                        ))
                        return
                    }

                    continuation.resume(returning: PTPTransaction(header: responseHeader, data: data))
                }
            }
        }
    }

    func closeSession() async throws {
        guard let camera = activeCamera else {
            return
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            camera.requestCloseSession(options: nil) { error in
                Task { @MainActor in
                    self.activeCamera = nil

                    if let error = error {
                        continuation.resume(throwing: CameraServiceError.underlying(error))
                    } else {
                        continuation.resume()
                    }
                }
            }
        }
    }

    private func updateDescriptor(for camera: ICCameraDevice) {
        let descriptor = CameraDescriptor(camera: camera)
        devicesByID[descriptor.id] = camera
        discoveredCameras.removeAll { $0.id == descriptor.id }
        discoveredCameras.append(descriptor)
        discoveredCameras.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func removeDescriptor(for device: ICDevice) {
        let id = device.uuidString ?? device.persistentIDString
        guard let id else {
            return
        }

        devicesByID.removeValue(forKey: id)
        discoveredCameras.removeAll { $0.id == id }

        if activeCamera?.uuidString == id || activeCamera?.persistentIDString == id {
            activeCamera = nil
        }
    }
}

private extension Data {
    var cameraSlotValue: UInt8? {
        switch count {
        case 1:
            return self[0]
        case 2:
            guard let value = readLittleEndianUInt16(at: 0), value <= UInt16(UInt8.max) else {
                return nil
            }
            return UInt8(value)
        default:
            return nil
        }
    }
}

extension ImageCaptureCameraService: ICDeviceBrowserDelegate {
    func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        guard let camera = device as? ICCameraDevice else {
            return
        }

        updateDescriptor(for: camera)
    }

    func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        removeDescriptor(for: device)
    }

    func deviceBrowserDidEnumerateLocalDevices(_ browser: ICDeviceBrowser) {}
}

private extension CameraDescriptor {
    init(camera: ICCameraDevice) {
        let id = camera.uuidString
            ?? camera.persistentIDString
            ?? "usb-\(camera.usbVendorID)-\(camera.usbProductID)-\(camera.name ?? "camera")"

        self.init(
            id: id,
            name: camera.name ?? camera.productKind ?? "Unknown camera",
            productKind: camera.productKind,
            serialNumber: camera.serialNumberString,
            transportType: camera.transportType,
            usbVendorID: camera.usbVendorID,
            usbProductID: camera.usbProductID,
            supportsPTP: camera.capabilities.contains(ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue)
        )
    }
}
