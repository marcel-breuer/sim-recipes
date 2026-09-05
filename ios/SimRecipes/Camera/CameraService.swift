import Foundation

struct CameraDescriptor: Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let productKind: String?
    let serialNumber: String?
    let transportType: String?
    let usbVendorID: Int32
    let usbProductID: Int32
    let supportsPTP: Bool

    var isX20Candidate: Bool {
        guard supportsPTP,
              transportType == "USB",
              usbVendorID > 0,
              usbProductID > 0 else {
            return false
        }

        let normalizedName = name
            .lowercased()
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        return normalizedName.contains("xs20")
    }
}

enum CameraServiceError: LocalizedError {
    case authorizationDenied
    case cameraNotFound(String)
    case unsupportedCamera
    case sessionNotOpen
    case ptpNotSupported
    case invalidPTPResponse
    case unexpectedPTPResponseCode(UInt16)
    case transactionMismatch(expected: UInt32, actual: UInt32)
    case underlying(Error)

    var errorDescription: String? {
        switch self {
        case .authorizationDenied:
            "Camera access was not authorized."
        case let .cameraNotFound(id):
            "Camera \(id) is no longer connected."
        case .unsupportedCamera:
            "The connected camera is not a Fujifilm X-S20 candidate."
        case .sessionNotOpen:
            "The camera session is not open."
        case .ptpNotSupported:
            "The camera does not report PTP command support."
        case .invalidPTPResponse:
            "The camera returned an invalid PTP response."
        case let .unexpectedPTPResponseCode(code):
            "The camera rejected the PTP command with response code 0x\(String(code, radix: 16))."
        case let .transactionMismatch(expected, actual):
            "The PTP transaction ID did not match (expected \(expected), received \(actual))."
        case let .underlying(error):
            error.localizedDescription
        }
    }
}

@MainActor
protocol CameraService: AnyObject {
    var discoveredCameras: [CameraDescriptor] { get }

    func requestControlAuthorization() async throws
    func startDiscovery()
    func stopDiscovery()
    func openSession(for cameraID: String) async throws
    func readDeviceInfo() async throws -> PTPResponseHeader
    func closeSession() async throws
}
