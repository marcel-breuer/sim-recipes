import Combine
import Foundation

@MainActor
final class ExploreViewModel: ObservableObject {
    @Published var feed: RecipeFeed = .popular
    @Published var searchText = ""
    @Published var selectedCameraID: String?
    @Published var selectedFilmSimulation: String?
    @Published var selectedCategorySlugs: Set<String> = []
    @Published var tagText = ""
    @Published private(set) var recipes: [RecipeTransport] = []
    @Published private(set) var cameras: [SupportedCameraTransport] = []
    @Published private(set) var categories: [CategoryTransport] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedFilters = false
    @Published var errorMessage: String?

    private let repository: RecipeRepository
    private let capabilityService: CameraCapabilityService
    private var currentPage = 0
    private var lastPage = 1

    init(repository: RecipeRepository, capabilityService: CameraCapabilityService) {
        self.repository = repository
        self.capabilityService = capabilityService
    }

    var hasMorePages: Bool {
        currentPage < lastPage
    }

    var filter: CommunityRecipeFilter {
        let tags = tagText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return CommunityRecipeFilter(
            search: searchText,
            cameraModelID: selectedCameraID,
            filmSimulation: selectedFilmSimulation,
            categorySlugs: selectedCategorySlugs.sorted(),
            tags: tags
        )
    }

    func loadInitial() async {
        guard !hasLoadedFilters else {
            if recipes.isEmpty {
                await refresh()
            }
            return
        }

        async let cameraResult = capabilityService.supportedCameras()
        async let categoryResult = capabilityService.categories()

        do {
            cameras = try await cameraResult
        } catch {
            errorMessage = error.localizedDescription
        }
        do {
            categories = try await categoryResult
        } catch {
            errorMessage = error.localizedDescription
        }
        hasLoadedFilters = true
        await refresh()
    }

    func refresh() async {
        guard !isLoading else { return }
        await loadPage(reset: true)
    }

    func loadNextPageIfNeeded(after recipe: RecipeTransport) async {
        guard recipe.id == recipes.last?.id, hasMorePages else { return }
        await loadPage(reset: false)
    }

    func applyFilters() async {
        await refresh()
    }

    private func loadPage(reset: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        let page = reset ? 1 : currentPage + 1
        do {
            let response = try await repository.communityRecipes(
                feed: feed,
                filter: filter,
                page: page
            )
            if reset {
                recipes = response.data
            } else {
                recipes.append(contentsOf: response.data)
            }
            currentPage = response.meta.currentPage
            lastPage = response.meta.lastPage
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
