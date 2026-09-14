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

struct CollectionRecipeTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let cameraModel: CameraModelTransport?
    let publishedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case cameraModel = "camera_model"
        case publishedAt = "published_at"
    }

    init(
        id: String,
        name: String,
        description: String? = nil,
        cameraModel: CameraModelTransport? = nil,
        publishedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.cameraModel = cameraModel
        self.publishedAt = publishedAt
    }
}

enum CollectionSyncState: String, Codable, Sendable {
    case synced
    case pendingCreate
    case pendingMembership
}

struct RecipeCollectionTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    var name: String
    var isPublic: Bool
    var sortOrder: Int
    var recipes: [CollectionRecipeTransport]
    var syncState: CollectionSyncState

    enum CodingKeys: String, CodingKey {
        case id, name, isPublic = "is_public", sortOrder = "sort_order", recipes, syncState
    }

    init(
        id: String,
        name: String,
        isPublic: Bool,
        sortOrder: Int,
        recipes: [CollectionRecipeTransport] = [],
        syncState: CollectionSyncState = .synced
    ) {
        self.id = id
        self.name = name
        self.isPublic = isPublic
        self.sortOrder = sortOrder
        self.recipes = recipes
        self.syncState = syncState
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        isPublic = try container.decode(Bool.self, forKey: .isPublic)
        sortOrder = try container.decodeIfPresent(Int.self, forKey: .sortOrder) ?? 0
        recipes = try container.decodeIfPresent([CollectionRecipeTransport].self, forKey: .recipes) ?? []
        syncState = try container.decodeIfPresent(CollectionSyncState.self, forKey: .syncState) ?? .synced
    }
}

struct CollectionNamePayload: Encodable, Sendable {
    let name: String
    let isPublic: Bool

    enum CodingKeys: String, CodingKey {
        case name
        case isPublic = "is_public"
    }
}

struct CollectionReorderPayload: Encodable, Sendable {
    let collectionIDs: [String]

    enum CodingKeys: String, CodingKey {
        case collectionIDs = "collection_ids"
    }
}

struct FollowResponse: Decodable, Sendable {
    let following: Bool
    let followersCount: Int

    enum CodingKeys: String, CodingKey {
        case following
        case followersCount = "followers_count"
    }
}

struct DeletedResponse: Decodable, Sendable {
    let deleted: Bool
}

struct ProfileTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let username: String
    let displayName: String
    let biography: String?
    let cameraModel: CameraModelTransport?
    let profileImageURL: URL?
    let publishedRecipes: [PublishedRecipeSummaryTransport]
    let collections: [RecipeCollectionTransport]
    let followersCount: Int
    let followingCount: Int
    let isFollowing: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case biography
        case cameraModel = "camera_model"
        case profileImageURL = "profile_image_url"
        case publishedRecipes = "published_recipes"
        case collections
        case followersCount = "followers_count"
        case followingCount = "following_count"
        case isFollowing = "is_following"
    }

    init(
        id: String,
        username: String,
        displayName: String,
        biography: String?,
        cameraModel: CameraModelTransport?,
        profileImageURL: URL?,
        publishedRecipes: [PublishedRecipeSummaryTransport],
        collections: [RecipeCollectionTransport] = [],
        followersCount: Int = 0,
        followingCount: Int = 0,
        isFollowing: Bool = false
    ) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.biography = biography
        self.cameraModel = cameraModel
        self.profileImageURL = profileImageURL
        self.publishedRecipes = publishedRecipes
        self.collections = collections
        self.followersCount = followersCount
        self.followingCount = followingCount
        self.isFollowing = isFollowing
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        username = try container.decode(String.self, forKey: .username)
        displayName = try container.decodeIfPresent(String.self, forKey: .displayName) ?? username
        biography = try container.decodeIfPresent(String.self, forKey: .biography)
        cameraModel = try container.decodeIfPresent(CameraModelTransport.self, forKey: .cameraModel)
        profileImageURL = try container.decodeIfPresent(URL.self, forKey: .profileImageURL)
        publishedRecipes = try container.decodeIfPresent([PublishedRecipeSummaryTransport].self, forKey: .publishedRecipes) ?? []
        collections = try container.decodeIfPresent([RecipeCollectionTransport].self, forKey: .collections) ?? []
        followersCount = try container.decodeIfPresent(Int.self, forKey: .followersCount) ?? 0
        followingCount = try container.decodeIfPresent(Int.self, forKey: .followingCount) ?? 0
        isFollowing = try container.decodeIfPresent(Bool.self, forKey: .isFollowing) ?? false
    }
}

final class LocalCollectionStore {
    private let defaults: UserDefaults
    private let key = "simrecipes.local.collections"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func collections() throws -> [RecipeCollectionTransport] {
        guard let data = defaults.data(forKey: key) else { return [] }
        return try JSONDecoder().decode([RecipeCollectionTransport].self, from: data)
    }

    func save(_ collections: [RecipeCollectionTransport]) throws {
        defaults.set(try JSONEncoder().encode(collections), forKey: key)
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
