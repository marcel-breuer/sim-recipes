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
        guard let camera = activeCamera, camera.hasOpenSession else {
            throw CameraServiceError.sessionNotOpen
        }

        guard camera.capabilities.contains(ICDeviceCapability.cameraDeviceCanAcceptPTPCommands.rawValue) else {
            throw CameraServiceError.ptpNotSupported
        }

        let command = PTPCommand.getDeviceInfo(transactionID: nextTransactionID)
        nextTransactionID = nextTransactionID == .max ? 1 : nextTransactionID + 1

        let responseData = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PTPResponseHeader, Error>) in
            camera.requestSendPTPCommand(command.encoded, outData: nil) { response, _, error in
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

                    continuation.resume(returning: responseHeader)
                }
            }
        }

        return responseData
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
