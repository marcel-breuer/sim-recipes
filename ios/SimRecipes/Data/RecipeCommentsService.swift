import Foundation

struct RecipeCommentAuthorTransport: Codable, Equatable, Sendable {
    let id: String
    let name: String
}

struct RecipeCommentTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let body: String
    let author: RecipeCommentAuthorTransport?
    let canDelete: Bool
    let createdAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, body, author
        case canDelete = "can_delete"
        case createdAt = "created_at"
    }
}

struct RecipeCommentPageTransport: Codable, Equatable, Sendable {
    let data: [RecipeCommentTransport]
    let meta: RecipePageMetadata
    let links: RecipePageLinks?
}

struct CreateRecipeCommentPayload: Encodable, Sendable {
    let body: String
}

struct RecipeCommentsService {
    private let apiClient: any APIClient

    init(apiClient: any APIClient) {
        self.apiClient = apiClient
    }

    func comments(for recipeID: String) async throws -> [RecipeCommentTransport] {
        let response = try await apiClient.send(
            APIRequest(method: .get, path: "recipes/\(recipeID)/comments"),
            responseType: APIResponse<RecipeCommentPageTransport>.self
        )
        return response.data.data
    }

    func addComment(to recipeID: String, body: String) async throws -> RecipeCommentTransport {
        let payload = try JSONEncoder().encode(CreateRecipeCommentPayload(body: body))
        let response = try await apiClient.send(
            APIRequest(method: .post, path: "recipes/\(recipeID)/comments", body: payload),
            responseType: APIResponse<RecipeCommentTransport>.self
        )
        return response.data
    }

    func deleteComment(id: String) async throws {
        _ = try await apiClient.send(
            APIRequest(method: .delete, path: "comments/\(id)"),
            responseType: APIResponse<DeletedResourceResponse>.self
        )
    }
}

private struct DeletedResourceResponse: Codable, Sendable {
    let deleted: Bool
}
