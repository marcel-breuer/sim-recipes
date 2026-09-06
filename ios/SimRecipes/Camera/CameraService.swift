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

enum CameraSessionState: Equatable, Sendable {
    case disconnected
    case opening(cameraID: String)
    case connected(cameraID: String)
}

enum CameraSlot: UInt8, CaseIterable, Sendable {
    case c1 = 1
    case c2 = 2
    case c3 = 3
    case c4 = 4
}

struct CameraSlotSnapshot: Equatable, Sendable {
    let slot: CameraSlot
    let properties: [UInt16: Data]
}

enum CameraSlotReadState: Equatable, Sendable {
    case notSelected
    case readable(propertyCount: Int)
}

struct CameraSlotDescriptor: Equatable, Identifiable, Sendable {
    let slot: CameraSlot
    let name: String?
    let readState: CameraSlotReadState

    var id: UInt8 { slot.rawValue }
}

enum CameraSlotDescriptorFactory {
    static func make(
        slots: [CameraSlot],
        currentSnapshot: CameraSlotSnapshot?
    ) -> [CameraSlotDescriptor] {
        slots.map { slot in
            if let currentSnapshot, currentSnapshot.slot == slot {
                return CameraSlotDescriptor(
                    slot: slot,
                    name: nil,
                    readState: .readable(propertyCount: currentSnapshot.properties.count)
                )
            }

            return CameraSlotDescriptor(slot: slot, name: nil, readState: .notSelected)
        }
    }
}

struct CameraSlotOverwriteConfirmation: Equatable, Sendable {
    let slot: CameraSlot

    init(slot: CameraSlot) {
        self.slot = slot
    }
}

enum CameraSlotWriteValidator {
    static func validationError(
        slot: CameraSlot,
        properties: [UInt16: Data],
        supportedPropertyCodes: Set<UInt16>,
        confirmation: CameraSlotOverwriteConfirmation
    ) -> CameraServiceError? {
        guard confirmation.slot == slot else {
            return .confirmationDoesNotMatchSlot
        }

        guard !properties.isEmpty else {
            return .noPropertiesToWrite
        }

        guard !properties.keys.contains(0xD18C) else {
            return .slotSelectorWriteForbidden
        }

        if let unsupportedProperty = properties.keys.first(where: { !supportedPropertyCodes.contains($0) }) {
            return .unsupportedProperty(unsupportedProperty)
        }

        return nil
    }
}

enum CameraServiceError: LocalizedError {
    case authorizationDenied
    case cameraNotFound(String)
    case unsupportedCamera
    case sessionNotOpen
    case ptpNotSupported
    case invalidSlotValue
    case requestedSlotIsNotSelected(expected: CameraSlot, actual: UInt8)
    case confirmationDoesNotMatchSlot
    case noPropertiesToWrite
    case unsupportedProperty(UInt16)
    case slotSelectorWriteForbidden
    case propertyVerificationFailed(UInt16)
    case rollbackFailed
    case invalidPTPResponse
    case unexpectedPTPResponseCode(UInt16)
    case transactionMismatch(expected: UInt32, actual: UInt32)
    case recipeTransferEncodingUnavailable
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
        case .invalidSlotValue:
            "The camera returned an invalid custom-slot value."
        case let .requestedSlotIsNotSelected(expected, actual):
            "The camera has slot C\(actual) selected instead of \(expected)."
        case .confirmationDoesNotMatchSlot:
            "The overwrite confirmation does not match the requested slot."
        case .noPropertiesToWrite:
            "The recipe does not contain any camera properties to write."
        case let .unsupportedProperty(propertyCode):
            "Property 0x\(String(propertyCode, radix: 16)) is not supported by the camera capability set."
        case .slotSelectorWriteForbidden:
            "The slot selector cannot be written by the recipe transfer operation."
        case let .propertyVerificationFailed(propertyCode):
            "Property 0x\(String(propertyCode, radix: 16)) did not match after read-back."
        case .rollbackFailed:
            "The camera rejected a rollback while recovering from a partial transfer."
        case .invalidPTPResponse:
            "The camera returned an invalid PTP response."
        case let .unexpectedPTPResponseCode(code):
            "The camera rejected the PTP command with response code 0x\(String(code, radix: 16))."
        case let .transactionMismatch(expected, actual):
            "The PTP transaction ID did not match (expected \(expected), received \(actual))."
        case .recipeTransferEncodingUnavailable:
            "This camera adapter cannot safely encode the recipe settings yet. No camera values were changed."
        case let .underlying(error):
            error.localizedDescription
        }
    }
}

@MainActor
protocol CameraService: AnyObject {
    var discoveredCameras: [CameraDescriptor] { get }
    var sessionState: CameraSessionState { get }

    func requestControlAuthorization() async throws
    func startDiscovery()
    func stopDiscovery()
    func openSession(for cameraID: String) async throws
    func readDeviceInfo() async throws -> PTPResponseHeader
    func readProperty(_ propertyCode: UInt16) async throws -> Data
    func availableSlots() async throws -> [CameraSlot]
    func readSlotDescriptors(propertyCodes: [UInt16]) async throws -> [CameraSlotDescriptor]
    func readCurrentSlotSnapshot(propertyCodes: [UInt16]) async throws -> CameraSlotSnapshot
    func readSelectedSlot(_ slot: CameraSlot, propertyCodes: [UInt16]) async throws -> CameraSlotSnapshot
    func transferRecipe(
        _ recipe: RecipeTransport,
        to slot: CameraSlot,
        confirmation: CameraSlotOverwriteConfirmation
    ) async throws -> CameraSlotSnapshot
    func writeRecipe(
        to slot: CameraSlot,
        properties: [UInt16: Data],
        supportedPropertyCodes: Set<UInt16>,
        confirmation: CameraSlotOverwriteConfirmation
    ) async throws -> CameraSlotSnapshot
    func closeSession() async throws
}
