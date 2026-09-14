import Foundation

struct ModerationReportTransport: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let reportableType: String
    let reportableID: String
    let reason: String
    let details: String?
    let status: String
    let resolution: String?

    enum CodingKeys: String, CodingKey {
        case id
        case reportableType = "reportable_type"
        case reportableID = "reportable_id"
        case reason, details, status, resolution
    }
}

struct ModerationActionResponse: Codable, Equatable, Sendable {
    let blocked: Bool
}

struct ModerationService {
    private let apiClient: any APIClient

    init(apiClient: any APIClient) {
        self.apiClient = apiClient
    }

    func reportRecipe(id: String, reason: String = "objectionable_content", details: String? = nil) async throws {
        try await report(path: "recipes/\(id)/reports", reason: reason, details: details)
    }

    func reportImage(id: String, reason: String = "objectionable_content", details: String? = nil) async throws {
        try await report(path: "recipe-images/\(id)/reports", reason: reason, details: details)
    }

    func reportComment(id: String, reason: String = "objectionable_content", details: String? = nil) async throws {
        try await report(path: "comments/\(id)/reports", reason: reason, details: details)
    }

    func reportUser(id: String, reason: String = "objectionable_content", details: String? = nil) async throws {
        try await report(path: "users/\(id)/reports", reason: reason, details: details)
    }

    func blockUser(id: String) async throws {
        _ = try await apiClient.send(
            APIRequest(method: .post, path: "users/\(id)/block"),
            responseType: APIResponse<ModerationActionResponse>.self
        )
    }

    func unblockUser(id: String) async throws {
        _ = try await apiClient.send(
            APIRequest(method: .delete, path: "users/\(id)/block"),
            responseType: APIResponse<ModerationActionResponse>.self
        )
    }

    private func report(path: String, reason: String, details: String?) async throws {
        let body = try JSONEncoder().encode(ReportBody(reason: reason, details: details))
        _ = try await apiClient.send(
            APIRequest(method: .post, path: path, body: body),
            responseType: APIResponse<ModerationReportTransport>.self
        )
    }
}

private struct ReportBody: Encodable {
    let reason: String
    let details: String?
}
