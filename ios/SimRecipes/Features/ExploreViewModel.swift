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
    @Published private(set) var savedFilters: [SavedRecipeFilter] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedFilters = false
    @Published var errorMessage: String?

    private let repository: RecipeRepository
    private let capabilityService: CameraCapabilityService
    private let savedFilterStore: SavedFilterStore
    private var currentPage = 0
    private var lastPage = 1

    init(
        repository: RecipeRepository,
        capabilityService: CameraCapabilityService,
        savedFilterStore: SavedFilterStore = SavedFilterStore()
    ) {
        self.repository = repository
        self.capabilityService = capabilityService
        self.savedFilterStore = savedFilterStore
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

        savedFilters = savedFilterStore.load()
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

    func applySavedFilter(_ savedFilter: SavedRecipeFilter) async {
        searchText = savedFilter.filter.search
        selectedCameraID = savedFilter.filter.cameraModelID
        selectedFilmSimulation = savedFilter.filter.filmSimulation
        selectedCategorySlugs = Set(savedFilter.filter.categorySlugs)
        tagText = savedFilter.filter.tags.joined(separator: ", ")
        await refresh()
    }

    func saveCurrentFilter(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        savedFilters.append(SavedRecipeFilter(
            id: UUID(),
            name: trimmedName,
            filter: filter
        ))
        savedFilterStore.save(savedFilters)
    }

    func renameSavedFilter(id: UUID, to name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty,
              let index = savedFilters.firstIndex(where: { $0.id == id }) else { return }
        savedFilters[index].name = trimmedName
        savedFilterStore.save(savedFilters)
    }

    func deleteSavedFilter(id: UUID) {
        savedFilters.removeAll { $0.id == id }
        savedFilterStore.save(savedFilters)
    }

    func moveSavedFilters(from source: IndexSet, to destination: Int) {
        savedFilters.move(fromOffsets: source, toOffset: destination)
        savedFilterStore.save(savedFilters)
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
