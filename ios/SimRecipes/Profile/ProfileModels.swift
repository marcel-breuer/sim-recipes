import Foundation

struct CameraModelTransport: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let slug: String
}

struct PublishedRecipeSummaryTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let cameraModel: CameraModelTransport?
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case cameraModel = "camera_model"
        case publishedAt = "published_at"
    }
}

struct ProfileTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let biography: String?
    let cameraModel: CameraModelTransport?
    let profileImageURL: URL?
    let publishedRecipes: [PublishedRecipeSummaryTransport]

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case biography
        case cameraModel = "camera_model"
        case profileImageURL = "profile_image_url"
        case publishedRecipes = "published_recipes"
    }
}

struct ProfileUpdatePayload: Encodable, Sendable {
    let username: String
    let cameraModelID: String?
    let biography: String?
    let removeProfileImage: Bool

    enum CodingKeys: String, CodingKey {
        case username
        case cameraModelID = "camera_model_id"
        case biography
        case removeProfileImage = "remove_profile_image"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(username, forKey: .username)
        try container.encode(cameraModelID, forKey: .cameraModelID)
        try container.encode(biography, forKey: .biography)
        try container.encode(removeProfileImage, forKey: .removeProfileImage)
    }
}
