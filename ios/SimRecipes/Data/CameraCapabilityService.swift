import Foundation

struct CameraCapabilityTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let key: String
    let displayName: String
    let valueType: String
    let allowedValues: JSONValue?
    let minimum: Double?
    let maximum: Double?
    let step: Double?

    enum CodingKeys: String, CodingKey {
        case id, key, displayName = "display_name", valueType = "value_type"
        case allowedValues = "allowed_values"
        case minimum, maximum, step
    }
}

struct SupportedCameraTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let manufacturer: String
    let name: String
    let slug: String
    let capabilities: [CameraCapabilityTransport]
}

struct CameraCapabilityService {
    private let apiClient: any APIClient

    init(apiClient: any APIClient) {
        self.apiClient = apiClient
    }

    func supportedCameras() async throws -> [SupportedCameraTransport] {
        let response = try await apiClient.send(
            APIRequest(method: .get, path: "cameras"),
            responseType: APIResponse<[SupportedCameraTransport]>.self
        )
        return response.data
    }

    func capabilities(for cameraID: String) async throws -> [CameraCapabilityTransport] {
        let response = try await apiClient.send(
            APIRequest(method: .get, path: "cameras/\(cameraID)/capabilities"),
            responseType: APIResponse<[CameraCapabilityTransport]>.self
        )
        return response.data
    }

    func categories() async throws -> [CategoryTransport] {
        let response = try await apiClient.send(
            APIRequest(method: .get, path: "categories"),
            responseType: APIResponse<[CategoryTransport]>.self
        )
        return response.data
    }
}
