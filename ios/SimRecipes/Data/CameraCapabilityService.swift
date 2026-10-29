import Foundation

struct CameraCapabilityEvidenceTransport: Codable, Equatable, Sendable {
    let level: String
    let source: String?
    let firmware: String?
    let verifiedAt: String?

    enum CodingKeys: String, CodingKey {
        case level, source, firmware
        case verifiedAt = "verified_at"
    }

    var evidenceLevel: CameraCompatibilityEvidenceLevel {
        CameraCompatibilityEvidenceLevel(rawValue: level) ?? .unknown
    }
}

struct CameraCapabilityTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let key: String
    let displayName: String
    let valueType: String
    let allowedValues: JSONValue?
    let minimum: Double?
    let maximum: Double?
    let step: Double?
    let evidence: CameraCapabilityEvidenceTransport?

    init(
        id: String,
        key: String,
        displayName: String,
        valueType: String,
        allowedValues: JSONValue?,
        minimum: Double?,
        maximum: Double?,
        step: Double?,
        evidence: CameraCapabilityEvidenceTransport? = nil
    ) {
        self.id = id
        self.key = key
        self.displayName = displayName
        self.valueType = valueType
        self.allowedValues = allowedValues
        self.minimum = minimum
        self.maximum = maximum
        self.step = step
        self.evidence = evidence
    }

    enum CodingKeys: String, CodingKey {
        case id, key, displayName = "display_name", valueType = "value_type"
        case allowedValues = "allowed_values"
        case minimum, maximum, step, evidence
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        key = try container.decode(String.self, forKey: .key)
        displayName = try container.decode(String.self, forKey: .displayName)
        valueType = try container.decode(String.self, forKey: .valueType)
        allowedValues = try container.decodeIfPresent(JSONValue.self, forKey: .allowedValues)
        minimum = try container.decodeIfPresent(Double.self, forKey: .minimum)
        maximum = try container.decodeIfPresent(Double.self, forKey: .maximum)
        step = try container.decodeIfPresent(Double.self, forKey: .step)
        evidence = try container.decodeIfPresent(CameraCapabilityEvidenceTransport.self, forKey: .evidence)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(key, forKey: .key)
        try container.encode(displayName, forKey: .displayName)
        try container.encode(valueType, forKey: .valueType)
        try container.encodeIfPresent(allowedValues, forKey: .allowedValues)
        try container.encodeIfPresent(minimum, forKey: .minimum)
        try container.encodeIfPresent(maximum, forKey: .maximum)
        try container.encodeIfPresent(step, forKey: .step)
        try container.encodeIfPresent(evidence, forKey: .evidence)
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
    private let localStore: CameraCapabilityLocalStore

    init(apiClient: any APIClient, localStore: CameraCapabilityLocalStore = CameraCapabilityLocalStore()) {
        self.apiClient = apiClient
        self.localStore = localStore
    }

    func supportedCameras() async throws -> [SupportedCameraTransport] {
        do {
            let response = try await apiClient.send(
                APIRequest(method: .get, path: "cameras"),
                responseType: APIResponse<[SupportedCameraTransport]>.self
            )
            try? localStore.save(response.data)
            return response.data
        } catch {
            let cached = try localStore.cameras()
            guard !cached.isEmpty else { throw error }
            return cached
        }
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

final class CameraCapabilityLocalStore {
    private let defaults: UserDefaults
    private let key = "simrecipes.camera.capabilities"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func cameras() throws -> [SupportedCameraTransport] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return try JSONDecoder().decode([SupportedCameraTransport].self, from: data)
    }

    func save(_ cameras: [SupportedCameraTransport]) throws {
        defaults.set(try JSONEncoder().encode(cameras), forKey: key)
    }
}
