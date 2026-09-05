import SwiftUI

struct LibraryView: View {
    @ObservedObject var authService: AuthService
    let apiClient: any APIClient
    let localStore: LocalRecipeStore
    @State private var recipes: [RecipeTransport] = []

    var body: some View {
        NavigationStack {
            Group {
                if authService.session == nil {
                    ContentUnavailableView(
                        "Sign in to build your library",
                        systemImage: "books.vertical",
                        description: Text("Private recipes and community copies remain available offline after sign-in.")
                    )
                } else if recipes.isEmpty {
                    ContentUnavailableView(
                        "Your library is empty",
                        systemImage: "books.vertical",
                        description: Text("Create a recipe or save one from the community to see it here.")
                    )
                } else {
                    List(recipes) { recipe in
                        NavigationLink {
                            editor(for: recipe)
                        } label: {
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
            .navigationTitle("Library")
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
                reloadRecipes()
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

    private func reloadRecipes() {
        recipes = (try? localStore.recipes()) ?? []
    }
}
