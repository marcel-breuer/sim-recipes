import SwiftUI

struct ExploreView: View {
    @ObservedObject private var authService: AuthService
    private let apiClient: any APIClient
    private let localStore: LocalRecipeStore
    private let cameraService: any CameraService
    @StateObject private var viewModel: ExploreViewModel
    @State private var showingFilters = false

    init(
        authService: AuthService,
        apiClient: any APIClient,
        localStore: LocalRecipeStore,
        cameraService: any CameraService
    ) {
        _authService = ObservedObject(wrappedValue: authService)
        self.apiClient = apiClient
        self.localStore = localStore
        self.cameraService = cameraService
        let repository = RecipeRepository(apiClient: apiClient, localStore: localStore)
        let capabilityService = CameraCapabilityService(apiClient: apiClient)
        _viewModel = StateObject(wrappedValue: ExploreViewModel(
            repository: repository,
            capabilityService: capabilityService
        ))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Feed", selection: $viewModel.feed) {
                    ForEach(RecipeFeed.allCases) { feed in
                        Text(feed.title).tag(feed)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .onChange(of: viewModel.feed) {
                    Task { await viewModel.refresh() }
                }

                Group {
                    if let errorMessage = viewModel.errorMessage, viewModel.recipes.isEmpty {
                        ContentUnavailableView {
                            Label("Unable to load recipes", systemImage: "wifi.exclamationmark")
                        } description: {
                            Text(errorMessage)
                        } actions: {
                            Button("Try again") {
                                Task { await viewModel.refresh() }
                            }
                        }
                    } else if viewModel.recipes.isEmpty, viewModel.isLoading {
                        ProgressView("Loading recipes…")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.recipes.isEmpty {
                        ContentUnavailableView(
                            "No recipes found",
                            systemImage: "camera.aperture",
                            description: Text("Try a different search or filter combination.")
                        )
                    } else {
                        recipeList
                    }
                }
            }
            .navigationTitle("Explore")
            .searchable(text: $viewModel.searchText, prompt: "Search recipes and tags")
            .onSubmit(of: .search) {
                Task { await viewModel.refresh() }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingFilters = true
                    } label: {
                        Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showingFilters) {
                ExploreFilterView(viewModel: viewModel)
                    .presentationDetents([.medium, .large])
            }
            .task {
                await viewModel.loadInitial()
            }
        }
    }

    private var recipeList: some View {
        List {
            ForEach(viewModel.recipes) { recipe in
                NavigationLink {
                    detail(for: recipe)
                } label: {
                    RecipeCard(recipe: recipe)
                }
                .task {
                    await viewModel.loadNextPageIfNeeded(after: recipe)
                }
            }

            if viewModel.isLoading && viewModel.hasMorePages {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await viewModel.refresh()
        }
    }

    @ViewBuilder
    private func detail(for recipe: RecipeTransport) -> some View {
        if let session = authService.session {
            let authenticatedClient = BearerAPIClient(apiClient: apiClient, accessToken: session.token)
            let repository = RecipeRepository(apiClient: authenticatedClient, localStore: localStore)
            let moderationService = ModerationService(apiClient: authenticatedClient)
            RecipeDetailView(
                recipe: recipe,
                transferService: transferService(for: recipe),
                capabilityService: CameraCapabilityService(apiClient: apiClient)
            ) {
                try await repository.copy(id: recipe.id)
            } viewAction: {
                try await repository.recordView(id: recipe.id)
            } likeAction: {
                try await repository.like(id: recipe.id)
            } unlikeAction: {
                try await repository.unlike(id: recipe.id)
            } reportAction: {
                try await moderationService.reportRecipe(id: recipe.id)
            } blockAction: {
                if let author = recipe.author {
                    try await moderationService.blockUser(id: author.id)
                }
            }
        } else {
            let repository = RecipeRepository(apiClient: apiClient, localStore: localStore)
            RecipeDetailView(
                recipe: recipe,
                transferService: transferService(for: recipe),
                capabilityService: CameraCapabilityService(apiClient: apiClient),
                viewAction: {
                try await repository.recordView(id: recipe.id)
                }
            )
        }
    }

    private func transferService(for recipe: RecipeTransport) -> (any CameraService)? {
        guard (try? localStore.recipe(id: recipe.id)) != nil else {
            return nil
        }
        return cameraService
    }
}

private struct RecipeCard: View {
    let recipe: RecipeTransport

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageURL = recipe.images.first?.localURL ?? recipe.images.first?.url {
                AsyncImage(url: imageURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Rectangle().fill(.quaternary)
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            Text(recipe.name)
                .font(.headline)
            Text(recipe.cameraModelID)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let recommendation = recipe.styleRecommendation, !recommendation.isEmpty {
                Text(recommendation)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            if !recipe.tags.isEmpty {
                Text(recipe.tags.map { "#\($0)" }.joined(separator: "  "))
                    .font(.caption)
                    .foregroundStyle(.tint)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct ExploreFilterView: View {
    @ObservedObject var viewModel: ExploreViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Camera") {
                    Picker("Camera model", selection: $viewModel.selectedCameraID) {
                        Text("Any camera").tag(nil as String?)
                        ForEach(viewModel.cameras) { camera in
                            Text(camera.name).tag(Optional(camera.id))
                        }
                    }
                    TextField("Film simulation", text: Binding(
                        get: { viewModel.selectedFilmSimulation ?? "" },
                        set: { viewModel.selectedFilmSimulation = $0.isEmpty ? nil : $0 }
                    ))
                }

                Section("Categories") {
                    ForEach(viewModel.categories) { category in
                        Toggle(category.name, isOn: Binding(
                            get: { viewModel.selectedCategorySlugs.contains(category.slug) },
                            set: { isSelected in
                                if isSelected {
                                    viewModel.selectedCategorySlugs.insert(category.slug)
                                } else {
                                    viewModel.selectedCategorySlugs.remove(category.slug)
                                }
                            }
                        ))
                    }
                }

                Section("Tags") {
                    TextField("Comma-separated tags", text: $viewModel.tagText)
                        .textInputAutocapitalization(.never)
                }
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        Task {
                            await viewModel.applyFilters()
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    ExploreView(
        authService: AuthService(apiClient: URLSessionAPIClient(baseURL: URL(string: "https://api.example.test/api/v1")!)),
        apiClient: URLSessionAPIClient(baseURL: URL(string: "https://api.example.test/api/v1")!),
        localStore: try! LocalRecipeStore(inMemory: true),
        cameraService: ImageCaptureCameraService()
    )
}
