import Foundation
import UIKit

enum RecipeImagePreparationError: LocalizedError, Equatable {
    case invalidImage
    case unableToEncode

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "The selected file is not a supported image."
        case .unableToEncode:
            "The selected image could not be prepared for upload."
        }
    }
}

enum RecipeImagePreparer {
    static let maxUploadBytes = 8 * 1024 * 1024
    static let maxPixelDimension: CGFloat = 4096

    static func prepare(
        _ data: Data,
        filename: String,
        id: UUID = UUID()
    ) throws -> RecipeDraftImage {
        guard let image = UIImage(data: data) else {
            throw RecipeImagePreparationError.invalidImage
        }

        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        let largestDimension = max(pixelWidth, pixelHeight)
        let initialScale = min(1, maxPixelDimension / max(largestDimension, 1))
        var size = CGSize(
            width: max(1, pixelWidth * initialScale),
            height: max(1, pixelHeight * initialScale)
        )

        for _ in 0..<5 {
            let rendered = render(image, size: size)
            for quality in [0.82, 0.70, 0.55, 0.40] {
                if let jpegData = rendered.jpegData(compressionQuality: quality),
                   jpegData.count <= maxUploadBytes {
                    return RecipeDraftImage(
                        id: id,
                        filename: URL(fileURLWithPath: filename).deletingPathExtension().lastPathComponent + ".jpg",
                        mimeType: "image/jpeg",
                        data: jpegData
                    )
                }
            }
            size = CGSize(width: size.width * 0.75, height: size.height * 0.75)
        }

        throw RecipeImagePreparationError.unableToEncode
    }

    private static func render(_ image: UIImage, size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIColor.white.setFill()
            UIRectFill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

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
