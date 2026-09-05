import SwiftUI

struct LibraryView: View {
    @ObservedObject var authService: AuthService
    let apiClient: any APIClient
    let localStore: LocalRecipeStore
    @State private var recipes: [RecipeTransport] = []
    @State private var searchText = ""

    private var filteredRecipes: [RecipeTransport] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return recipes }

        return recipes.filter { recipe in
            [recipe.name, recipe.description ?? "", recipe.styleRecommendation ?? ""]
                .plus(recipe.categories)
                .plus(recipe.tags)
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if authService.session == nil {
                    ContentUnavailableView(
                        "Sign in to build your library",
                        systemImage: "books.vertical",
                        description: Text("Private recipes and community copies remain available offline after sign-in.")
                    )
                } else if filteredRecipes.isEmpty {
                    ContentUnavailableView(
                        recipes.isEmpty ? "Your library is empty" : "No matching recipes",
                        systemImage: "books.vertical",
                        description: Text(recipes.isEmpty
                            ? "Create a recipe or save one from the community to see it here."
                            : "Try a different local search.")
                    )
                } else {
                    List(filteredRecipes) { recipe in
                        NavigationLink {
                            editor(for: recipe)
                        } label: {
                            HStack(spacing: 12) {
                                if let imageURL = recipe.images.first?.localURL {
                                    AsyncImage(url: imageURL) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: {
                                        Rectangle().fill(.quaternary)
                                    }
                                    .frame(width: 56, height: 56)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(recipe.name)
                                        .font(.headline)
                                    Text(recipe.isPublished ? "Published" : "Private draft")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search your library")
            .toolbar {
                if authService.session != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        NavigationLink {
                            editor(for: nil)
                        } label: {
                            Label("New recipe", systemImage: "plus")
                        }
                    }
                }
            }
            .task(id: authService.session?.token) {
                await syncAndReload()
            }
        }
    }

    @ViewBuilder
    private func editor(for recipe: RecipeTransport?) -> some View {
        if let session = authService.session {
            let authenticatedClient = BearerAPIClient(apiClient: apiClient, accessToken: session.token)
            let repository = RecipeRepository(apiClient: authenticatedClient, localStore: localStore)
            let capabilityService = CameraCapabilityService(apiClient: authenticatedClient)
            RecipeEditorView(
                viewModel: RecipeEditorViewModel(
                    draft: recipe.map(RecipeDraft.init) ?? RecipeDraft(),
                    repository: repository,
                    capabilityService: capabilityService
                )
            )
        }
    }

    private func syncAndReload() async {
        reloadRecipes()
        guard let session = authService.session else { return }

        let authenticatedClient = BearerAPIClient(apiClient: apiClient, accessToken: session.token)
        let repository = RecipeRepository(apiClient: authenticatedClient, localStore: localStore)
        _ = try? await repository.refreshRecipes()
        reloadRecipes()
    }

    private func reloadRecipes() {
        recipes = (try? localStore.recipes()) ?? []
    }
}

private extension Array where Element == String {
    func plus(_ values: [String]) -> [String] {
        self + values
    }
}
