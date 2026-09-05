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

struct CommunityRecipeFilter: Equatable, Sendable {
    var search = ""
    var cameraModelID: String?
    var filmSimulation: String?
    var categorySlugs: [String] = []
    var tags: [String] = []
}
