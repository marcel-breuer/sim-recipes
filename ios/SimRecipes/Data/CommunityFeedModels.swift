import Foundation

enum RecipeFeed: String, CaseIterable, Identifiable, Sendable {
    case popular
    case newest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .popular:
            "Popular"
        case .newest:
            "New"
        }
    }
}

struct CommunityRecipeFilter: Codable, Equatable, Sendable {
    var search = ""
    var cameraModelID: String?
    var compatibilityEvidence: String? = nil
    var filmSimulation: String?
    var categorySlugs: [String] = []
    var tags: [String] = []
}

enum CompatibilityEvidenceFilter: CaseIterable, Hashable, Identifiable, Sendable {
    case any
    case manufacturerDocumented
    case cameraVerified

    var id: String {
        switch self {
        case .any: "any"
        case .manufacturerDocumented: "manufacturer_documented"
        case .cameraVerified: "camera_verified"
        }
    }

    var apiValue: String? {
        switch self {
        case .any: nil
        case .manufacturerDocumented: "manufacturer_documented"
        case .cameraVerified: "camera_verified"
        }
    }

    var title: String {
        switch self {
        case .any: "Any evidence level"
        case .manufacturerDocumented: "Manufacturer documented or better"
        case .cameraVerified: "Camera verified"
        }
    }

    init(apiValue: String?) {
        switch apiValue {
        case "manufacturer_documented": self = .manufacturerDocumented
        case "camera_verified": self = .cameraVerified
        default: self = .any
        }
    }
}

struct SavedRecipeFilter: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var filter: CommunityRecipeFilter
}
