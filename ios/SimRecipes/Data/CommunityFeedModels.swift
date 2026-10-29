import Foundation

struct RecipeContextTag: Hashable, Identifiable, Sendable {
    let id: String
    let title: String

    init(_ id: String, _ title: String) {
        self.id = id
        self.title = title
    }
}

enum RecipeExampleContextOptions {
    static let subjects = [
        RecipeContextTag("street", "Street"),
        RecipeContextTag("portrait", "Portrait"),
        RecipeContextTag("landscape", "Landscape"),
        RecipeContextTag("architecture", "Architecture"),
        RecipeContextTag("nature", "Nature"),
        RecipeContextTag("wildlife", "Wildlife"),
        RecipeContextTag("travel", "Travel"),
        RecipeContextTag("automotive", "Automotive"),
        RecipeContextTag("night", "Night"),
        RecipeContextTag("low_light", "Low light"),
        RecipeContextTag("indoor", "Indoor"),
        RecipeContextTag("food", "Food"),
        RecipeContextTag("everyday", "Everyday"),
        RecipeContextTag("documentary", "Documentary"),
        RecipeContextTag("close_up", "Close-up")
    ]

    static let lighting = [
        RecipeContextTag("daylight", "Daylight"),
        RecipeContextTag("golden_hour", "Golden hour"),
        RecipeContextTag("blue_hour", "Blue hour"),
        RecipeContextTag("overcast", "Overcast"),
        RecipeContextTag("open_shade", "Open shade"),
        RecipeContextTag("backlit", "Backlit"),
        RecipeContextTag("artificial", "Artificial light"),
        RecipeContextTag("mixed", "Mixed light"),
        RecipeContextTag("low_light", "Low light"),
        RecipeContextTag("studio", "Studio")
    ]

    static let looks = [
        RecipeContextTag("warm", "Warm"),
        RecipeContextTag("neutral", "Neutral"),
        RecipeContextTag("cool", "Cool"),
        RecipeContextTag("monochrome", "Monochrome"),
        RecipeContextTag("vibrant", "Vibrant"),
        RecipeContextTag("muted", "Muted"),
        RecipeContextTag("cinematic", "Cinematic"),
        RecipeContextTag("vintage", "Vintage")
    ]

    static func title(for id: String, in options: [RecipeContextTag]) -> String {
        options.first(where: { $0.id == id })?.title ?? id.replacingOccurrences(of: "_", with: " ").capitalized
    }
}

struct RecipeExampleContext: Codable, Equatable, Sendable {
    var subjects: [String] = []
    var lighting: [String] = []
    var looks: [String] = []

    var hasLabels: Bool {
        !subjects.isEmpty || !lighting.isEmpty || !looks.isEmpty
    }

    var displayLabels: [String] {
        subjects.map { RecipeExampleContextOptions.title(for: $0, in: RecipeExampleContextOptions.subjects) }
            + lighting.map { RecipeExampleContextOptions.title(for: $0, in: RecipeExampleContextOptions.lighting) }
            + looks.map { RecipeExampleContextOptions.title(for: $0, in: RecipeExampleContextOptions.looks) }
    }
}

struct RecipeExampleContextFilter: Codable, Equatable, Sendable {
    var subjects: [String] = []
    var lighting: [String] = []
    var looks: [String] = []

    var isEmpty: Bool {
        subjects.isEmpty && lighting.isEmpty && looks.isEmpty
    }

    func matches(_ context: RecipeExampleContext?) -> Bool {
        guard let context else { return false }
        return matchesAny(subjects, in: context.subjects)
            && matchesAny(lighting, in: context.lighting)
            && matchesAny(looks, in: context.looks)
    }

    private func matchesAny(_ selected: [String], in available: [String]) -> Bool {
        selected.isEmpty || !Set(selected).isDisjoint(with: available)
    }
}

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
    var exampleContext: RecipeExampleContextFilter? = nil
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
