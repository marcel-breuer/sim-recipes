import Foundation

struct CategoryTransport: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let name: String
    let slug: String
}

struct RecipeDraftImage: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let filename: String
    let mimeType: String
    let data: Data

    init(id: UUID = UUID(), filename: String, mimeType: String = "image/jpeg", data: Data) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
    }
}

struct RecipeDraft: Codable, Equatable, Identifiable, Sendable {
    var id: String?
    var name = ""
    var description = ""
    var recommendation = ""
    var cameraModelID = ""
    var lens = ""
    var categories: [String] = []
    var tags: [String] = []
    var settings: [RecipeSettingTransport] = []
    var images: [RecipeDraftImage] = []
    var existingImageCount = 0
    var isPublished = false

    var totalImageCount: Int {
        existingImageCount + images.count
    }

    var transportID: String {
        id ?? "draft-\(UUID().uuidString.lowercased())"
    }

    init(recipe: RecipeTransport) {
        id = recipe.id
        name = recipe.name
        description = recipe.description ?? ""
        recommendation = recipe.styleRecommendation ?? ""
        cameraModelID = recipe.cameraModelID
        lens = recipe.lens ?? ""
        categories = recipe.categories
        tags = recipe.tags
        settings = recipe.settings
        existingImageCount = recipe.images.count
        isPublished = recipe.isPublished
    }

    init() {}

    func transport(updatedAt: Date = Date()) -> RecipeTransport {
        RecipeTransport(
            id: transportID,
            name: name,
            description: description.isEmpty ? nil : description,
            styleRecommendation: recommendation.isEmpty ? nil : recommendation,
            cameraModelID: cameraModelID,
            lens: lens.isEmpty ? nil : lens,
            categories: categories,
            tags: tags,
            isPublished: isPublished,
            provenance: nil,
            updatedAt: updatedAt,
            settings: settings
        )
    }
}

enum RecipeDraftValidationError: LocalizedError, Equatable {
    case nameRequired
    case cameraRequired
    case imageRequired
    case tooManyImages
    case publishedRecipeIsImmutable

    var errorDescription: String? {
        switch self {
        case .nameRequired:
            "Enter a recipe name."
        case .cameraRequired:
            "Choose a supported camera."
        case .imageRequired:
            "Add at least one example image before saving."
        case .tooManyImages:
            "A recipe can contain at most five example images."
        case .publishedRecipeIsImmutable:
            "Published recipes are immutable. Duplicate the recipe to make changes."
        }
    }
}
