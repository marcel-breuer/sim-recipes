import Foundation

enum JSONValue: Codable, Equatable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    var stringValue: String? {
        guard case let .string(value) = self else { return nil }
        return value
    }

    var numberValue: Double? {
        guard case let .number(value) = self else { return nil }
        return value
    }
}

extension JSONValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
}

struct RecipeImageTransport: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let url: URL?
    let derivativeURLs: [String: URL]
    let processingStatus: String
    let localURL: URL?

    init(
        id: String,
        url: URL?,
        derivativeURLs: [String: URL],
        processingStatus: String,
        localURL: URL? = nil
    ) {
        self.id = id
        self.url = url
        self.derivativeURLs = derivativeURLs
        self.processingStatus = processingStatus
        self.localURL = localURL
    }

    enum CodingKeys: String, CodingKey {
        case id
        case url
        case derivativeURLs = "derivative_urls"
        case processingStatus = "processing_status"
        case localURL = "local_url"
    }
}

struct RecipeTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let description: String?
    let styleRecommendation: String?
    let cameraModelID: String
    let cameraModelName: String?
    let lens: String?
    let categories: [String]
    let tags: [String]
    let isPublished: Bool
    let provenance: RecipeProvenanceTransport?
    let updatedAt: Date
    let settings: [RecipeSettingTransport]
    let images: [RecipeImageTransport]
    let author: RecipeAuthorTransport?
    let publishedAt: Date?
    let viewsCount: Int
    let likesCount: Int
    let downloadsCount: Int
    let isLiked: Bool?

    init(
        id: String,
        name: String,
        description: String?,
        styleRecommendation: String?,
        cameraModelID: String,
        cameraModelName: String? = nil,
        lens: String?,
        categories: [String],
        tags: [String],
        isPublished: Bool,
        provenance: RecipeProvenanceTransport?,
        updatedAt: Date,
        settings: [RecipeSettingTransport],
        images: [RecipeImageTransport] = [],
        author: RecipeAuthorTransport? = nil,
        publishedAt: Date? = nil,
        viewsCount: Int = 0,
        likesCount: Int = 0,
        downloadsCount: Int = 0,
        isLiked: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.styleRecommendation = styleRecommendation
        self.cameraModelID = cameraModelID
        self.cameraModelName = cameraModelName
        self.lens = lens
        self.categories = categories
        self.tags = tags
        self.isPublished = isPublished
        self.provenance = provenance
        self.updatedAt = updatedAt
        self.settings = settings
        self.images = images
        self.author = author
        self.publishedAt = publishedAt
        self.viewsCount = viewsCount
        self.likesCount = likesCount
        self.downloadsCount = downloadsCount
        self.isLiked = isLiked
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, description, recommendation, styleRecommendation = "style_recommendation"
        case cameraModelID = "camera_model_id"
        case cameraModel = "camera_model"
        case lens, categories, tags, status, isPublished = "is_published"
        case provenance, author, publishedAt = "published_at"
        case updatedAt = "updated_at", createdAt = "created_at"
        case viewsCount = "views_count", likesCount = "likes_count", downloadsCount = "downloads_count"
        case isLiked = "liked_by_current_user"
        case settings, images
    }

    private struct NamedReference: Codable {
        let id: String?
        let name: String?
        let slug: String?
    }

    private struct CameraReference: Codable {
        let id: String
        let name: String?
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        let recommendation = try container.decodeIfPresent(String.self, forKey: .recommendation)
        let legacyRecommendation = try container.decodeIfPresent(String.self, forKey: .styleRecommendation)
        styleRecommendation = recommendation ?? legacyRecommendation

        if let cameraModelID = try container.decodeIfPresent(String.self, forKey: .cameraModelID) {
            self.cameraModelID = cameraModelID
            cameraModelName = nil
        } else {
            let camera = try container.decode(CameraReference.self, forKey: .cameraModel)
            self.cameraModelID = camera.id
            cameraModelName = camera.name
        }

        lens = try container.decodeIfPresent(String.self, forKey: .lens)
        categories = try Self.decodeNames(container, key: .categories)
        tags = try Self.decodeNames(container, key: .tags)
        if let published = try container.decodeIfPresent(Bool.self, forKey: .isPublished) {
            isPublished = published
        } else {
            isPublished = try container.decodeIfPresent(String.self, forKey: .status) == "published"
        }
        provenance = try container.decodeIfPresent(RecipeProvenanceTransport.self, forKey: .provenance)
        let updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
        let createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt)
        self.updatedAt = updatedAt ?? createdAt ?? Date()
        settings = try container.decodeIfPresent([RecipeSettingTransport].self, forKey: .settings) ?? []
        images = try container.decodeIfPresent([RecipeImageTransport].self, forKey: .images) ?? []
        author = try container.decodeIfPresent(RecipeAuthorTransport.self, forKey: .author)
        publishedAt = try container.decodeIfPresent(Date.self, forKey: .publishedAt)
        viewsCount = try container.decodeIfPresent(Int.self, forKey: .viewsCount) ?? 0
        likesCount = try container.decodeIfPresent(Int.self, forKey: .likesCount) ?? 0
        downloadsCount = try container.decodeIfPresent(Int.self, forKey: .downloadsCount) ?? 0
        isLiked = try container.decodeIfPresent(Bool.self, forKey: .isLiked)
    }

    private static func decodeNames(
        _ container: KeyedDecodingContainer<CodingKeys>,
        key: CodingKeys
    ) throws -> [String] {
        if let names = try? container.decode([String].self, forKey: key) {
            return names
        }

        return try container.decodeIfPresent([NamedReference].self, forKey: key)?.compactMap { $0.name } ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(styleRecommendation, forKey: .recommendation)
        try container.encode(cameraModelID, forKey: .cameraModelID)
        try container.encodeIfPresent(lens, forKey: .lens)
        try container.encode(categories, forKey: .categories)
        try container.encode(tags, forKey: .tags)
        try container.encode(isPublished, forKey: .isPublished)
        try container.encodeIfPresent(provenance, forKey: .provenance)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(settings, forKey: .settings)
        try container.encode(images, forKey: .images)
        try container.encodeIfPresent(author, forKey: .author)
        try container.encodeIfPresent(publishedAt, forKey: .publishedAt)
        try container.encode(viewsCount, forKey: .viewsCount)
        try container.encode(likesCount, forKey: .likesCount)
        try container.encode(downloadsCount, forKey: .downloadsCount)
        try container.encodeIfPresent(isLiked, forKey: .isLiked)
    }
}

struct RecipeAuthorTransport: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let username: String?

    init(id: String, name: String, username: String? = nil) {
        self.id = id
        self.name = name
        self.username = username
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, username
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        username = try container.decodeIfPresent(String.self, forKey: .username)
    }
}

struct RecipeProvenanceTransport: Codable, Equatable, Sendable {
    let sourceRecipeID: String?
    let sourceAuthorID: String?

    enum CodingKeys: String, CodingKey {
        case sourceRecipeID = "source_recipe_id"
        case sourceAuthorID = "source_author_id"
    }
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
    let value: JSONValue
}
