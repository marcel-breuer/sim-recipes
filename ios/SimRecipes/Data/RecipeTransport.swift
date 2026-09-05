import Foundation

struct RecipeTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let styleRecommendation: String?
    let cameraModelID: String
    let lens: String?
    let categories: [String]
    let tags: [String]
    let isPublished: Bool
    let provenance: RecipeProvenanceTransport?
    let updatedAt: Date
    let settings: [RecipeSettingTransport]
}

struct RecipeProvenanceTransport: Codable, Equatable, Sendable {
    let sourceRecipeID: String?
    let sourceAuthorID: String?
}

struct RecipePageTransport: Codable, Equatable, Sendable {
    let data: [RecipeTransport]
    let meta: RecipePageMetadata
    let links: RecipePageLinks?
}

struct RecipePageMetadata: Codable, Equatable, Sendable {
    let currentPage: Int
    let lastPage: Int
    let perPage: Int
    let total: Int

    enum CodingKeys: String, CodingKey {
        case currentPage = "current_page"
        case lastPage = "last_page"
        case perPage = "per_page"
        case total
    }
}

struct RecipePageLinks: Codable, Equatable, Sendable {
    let next: URL?
}

enum RecipeSyncState: String, Codable, Sendable {
    case localOnly
    case synced
    case pendingUpload
    case conflict
}

struct RecipeSettingTransport: Codable, Equatable, Sendable {
    let key: String
    let value: String
}
