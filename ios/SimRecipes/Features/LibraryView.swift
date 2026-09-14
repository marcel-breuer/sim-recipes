import SwiftUI

struct LibraryView: View {
    @ObservedObject var authService: AuthService
    let apiClient: any APIClient
    let localStore: LocalRecipeStore
    let cameraService: any CameraService
    @State private var recipes: [RecipeTransport] = []
    @State private var searchText = ""
    @State private var showingImporter = false
    @State private var exportDocument: SimRecipeFileDocument?
    @State private var showingExporter = false
    @State private var exportFilename = "recipe.simrecipe"
    @State private var message: String?

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
                                recipeRow(recipe)
                            }
                        }
                        .contextMenu {
                            Button {
                                beginExport(recipe)
                            } label: {
                                Label("Export recipe", systemImage: "square.and.arrow.up")
                            }
                            if let shareURL = RecipeShareLink.url(for: recipe) {
                                ShareLink(item: shareURL) {
                                    Label("Share public link", systemImage: "link")
                                }
                            }
                            NavigationLink {
                                transfer(for: recipe)
                            } label: {
                                Label("Transfer to Camera", systemImage: "arrow.down.to.line.compact")
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            NavigationLink {
                                transfer(for: recipe)
                            } label: {
                                Label("Transfer", systemImage: "arrow.down.to.line.compact")
                            }
                            .tint(.accentColor)
                        }
                    }
                }
            }
            .navigationTitle("Library")
            .searchable(text: $searchText, prompt: "Search your library")
            .toolbar {
                if authService.session != nil {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import recipe", systemImage: "square.and.arrow.down")
                        }
                    }
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
            .fileImporter(
                isPresented: $showingImporter,
                allowedContentTypes: [.simRecipe]
            ) { result in
                Task { await importRecipe(result) }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .simRecipe,
                defaultFilename: exportFilename
            ) { result in
                if case let .failure(error) = result {
                    message = error.localizedDescription
                }
            }
            .alert("Recipe portability", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("OK") { message = nil }
            } message: {
                Text(message ?? "")
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

    @ViewBuilder
    private func transfer(for recipe: RecipeTransport) -> some View {
        CameraTransferView(recipe: recipe, cameraService: cameraService)
    }

    @ViewBuilder
    private func recipeRow(_ recipe: RecipeTransport) -> some View {
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

    private func syncAndReload() async {
        reloadRecipes()
        guard let session = authService.session else { return }

        let authenticatedClient = BearerAPIClient(apiClient: apiClient, accessToken: session.token)
        let repository = RecipeRepository(apiClient: authenticatedClient, localStore: localStore)
        _ = try? await repository.refreshRecipes()
        reloadRecipes()
    }

    private func beginExport(_ recipe: RecipeTransport) {
        do {
            exportDocument = SimRecipeFileDocument(data: try RecipePortabilityService.exportData(recipe: recipe))
            exportFilename = "\(recipe.name.replacingOccurrences(of: " ", with: "-")).simrecipe"
            showingExporter = true
        } catch {
            message = error.localizedDescription
        }
    }

    private func importRecipe(_ result: Result<URL, Error>) async {
        do {
            let url = try result.get()
            let data = try Data(contentsOf: url)
            let cameras = try await CameraCapabilityService(apiClient: apiClient).supportedCameras()
            let draft = try RecipePortabilityService.importDraft(from: data, supportedCameras: cameras)
            try localStore.saveLocally(draft.transport())
            reloadRecipes()
            message = "The recipe was imported as a local draft."
        } catch {
            message = error.localizedDescription
        }
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
