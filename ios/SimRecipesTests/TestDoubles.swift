import Foundation
@testable import SimRecipes

final class StubAPIClient: APIClient {
    private var responses: [Any]
    private(set) var requests: [String] = []

    init(responses: [Any] = []) {
        self.responses = responses
    }

    func send<Response: Decodable>(
        _ request: APIRequest,
        responseType: Response.Type
    ) async throws -> Response {
        requests.append(request.path)
        guard !responses.isEmpty else {
            throw APIClientError.invalidResponse
        }

        let response = responses.removeFirst()
        guard let response = response as? Response else {
            throw APIClientError.decoding(
                NSError(domain: "StubAPIClient", code: 1, userInfo: nil)
            )
        }

        return response
    }

    func download(_ request: APIRequest) async throws -> Data {
        throw APIClientError.invalidResponse
    }
}

final class MemoryCredentialStore: CredentialStore {
    var data: Data?

    func read() throws -> Data? {
        data
    }

    func write(_ data: Data) throws {
        self.data = data
    }

    func delete() throws {
        data = nil
    }
}

@MainActor
final class StubCameraService: CameraService {
    var discoveredCameras: [CameraDescriptor]
    var slots: [CameraSlot] = CameraSlot.allCases
    var currentSnapshot = CameraSlotSnapshot(slot: .c1, properties: [:])
    var transferError: Error?
    private(set) var transferredRecipeID: String?

    init(discoveredCameras: [CameraDescriptor] = []) {
        self.discoveredCameras = discoveredCameras
    }

    func requestControlAuthorization() async throws {}
    func startDiscovery() {}
    func stopDiscovery() {}
    func openSession(for cameraID: String) async throws {}
    func readDeviceInfo() async throws -> PTPResponseHeader {
        PTPResponseHeader(length: 12, type: 3, responseCode: 0x2001, transactionID: 1)
    }
    func readProperty(_ propertyCode: UInt16) async throws -> Data { Data([0]) }
    func availableSlots() async throws -> [CameraSlot] { slots }
    func readCurrentSlotSnapshot(propertyCodes: [UInt16]) async throws -> CameraSlotSnapshot {
        currentSnapshot
    }
    func readSelectedSlot(_ slot: CameraSlot, propertyCodes: [UInt16]) async throws -> CameraSlotSnapshot {
        currentSnapshot
    }
    func transferRecipe(
        _ recipe: RecipeTransport,
        to slot: CameraSlot,
        confirmation: CameraSlotOverwriteConfirmation
    ) async throws -> CameraSlotSnapshot {
        if let transferError {
            throw transferError
        }
        transferredRecipeID = recipe.id
        return CameraSlotSnapshot(slot: slot, properties: [:])
    }
    func writeRecipe(
        to slot: CameraSlot,
        properties: [UInt16: Data],
        supportedPropertyCodes: Set<UInt16>,
        confirmation: CameraSlotOverwriteConfirmation
    ) async throws -> CameraSlotSnapshot {
        CameraSlotSnapshot(slot: slot, properties: properties)
    }
    func closeSession() async throws {}
}
