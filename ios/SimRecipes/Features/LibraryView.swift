import SwiftUI

struct LibraryView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var profileService: ProfileService
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
    @State private var shareCardRecipe: RecipeTransport?
    @State private var showingDarkroom = false
    @State private var showingCameraKit = false
    @State private var showingLocalFilters = false
    @State private var selectedLocalCameraID: String?
    @State private var selectedLocalEvidence: CompatibilityEvidenceFilter = .any
    @State private var selectedLocalFilmSimulation: String?
    @State private var selectedLocalCategories: Set<String> = []
    @State private var localTagFilterText = ""
    @State private var selectedLocalSubjects: Set<String> = []
    @State private var selectedLocalLighting: Set<String> = []
    @State private var selectedLocalLooks: Set<String> = []

    private var filteredRecipes: [RecipeTransport] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let contextFilter = RecipeExampleContextFilter(
            subjects: selectedLocalSubjects.sorted(),
            lighting: selectedLocalLighting.sorted(),
            looks: selectedLocalLooks.sorted()
        )
        let selectedTags = localTagFilterText
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return recipes.filter { recipe in
            if let selectedLocalCameraID, recipe.cameraModelID != selectedLocalCameraID { return false }
            if selectedLocalEvidence != .any,
               !meetsCompatibilityEvidence(recipe, filter: selectedLocalEvidence) { return false }
            if let selectedLocalFilmSimulation,
               !recipe.settings.contains(where: { $0.key == "film_simulation" && $0.value.stringValue == selectedLocalFilmSimulation }) {
                return false
            }
            if !selectedLocalCategories.isEmpty,
               Set(recipe.categories).isDisjoint(with: selectedLocalCategories) { return false }
            if !selectedTags.isEmpty,
               Set(recipe.tags.map { $0.lowercased() }).isDisjoint(with: Set(selectedTags.map { $0.lowercased() })) { return false }
            if !contextFilter.isEmpty,
               !recipe.images.contains(where: { contextFilter.matches($0.exampleContext) }) {
                return false
            }
            guard !query.isEmpty else { return true }

            let imageText = recipe.images.flatMap { image in
                (image.exampleContext?.displayLabels ?? [])
                    + [image.captureMetadata?.sceneNotes ?? "", image.captureMetadata?.lightingNotes ?? ""]
            }
            return ([recipe.name, recipe.description ?? "", recipe.styleRecommendation ?? ""]
                .plus(recipe.categories)
                .plus(recipe.tags)
                .plus(imageText)
                .contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    private var localCameraOptions: [LocalCameraFilterOption] {
        let cameras = cachedCameras
        let namesByID = Dictionary(uniqueKeysWithValues: cameras.map { ($0.id, $0.name) })
        return Set(recipes.map(\.cameraModelID)).sorted().map { id in
            LocalCameraFilterOption(id: id, name: namesByID[id] ?? id)
        }
    }

    private var cachedCameras: [SupportedCameraTransport] {
        (try? CameraCapabilityLocalStore().cameras()) ?? []
    }

    private var localFilmSimulationOptions: [String] {
        Set(recipes.flatMap { recipe in
            recipe.settings
                .filter { $0.key == "film_simulation" }
                .compactMap { $0.value.stringValue }
        }).sorted()
    }

    private var localCategoryOptions: [String] {
        Set(recipes.flatMap(\.categories)).sorted()
    }

    private func meetsCompatibilityEvidence(
        _ recipe: RecipeTransport,
        filter: CompatibilityEvidenceFilter
    ) -> Bool {
        guard filter != .any,
              !recipe.settings.isEmpty,
              let camera = cachedCameras.first(where: { $0.id == recipe.cameraModelID }) else { return false }
        let minimumConfidence = filter == .cameraVerified ? 3 : 2
        return recipe.settings.allSatisfy { setting in
            guard let capability = camera.capabilities.first(where: { $0.key == setting.key }),
                  let evidence = capability.evidence else { return false }
            return evidence.evidenceLevel.confidence >= minimumConfidence
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
                            : "Try a different search, camera, or example-context filter.")
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
                            Button {
                                shareCardRecipe = recipe
                            } label: {
                                Label("Create recipe card", systemImage: "rectangle.portrait.on.rectangle.portrait")
                            }
                            if let shareURL = RecipeShareLink.url(for: recipe) {
                                ShareLink(item: shareURL) {
                                    Label("Share public link", systemImage: "link")
                                }
                            }
                            let state = syncState(for: recipe)
                            if state == .failed {
                                Button {
                                    Task { await retry(recipe) }
                                } label: {
                                    Label("Retry sync", systemImage: "arrow.clockwise")
                                }
                            }
                            if state == .conflict {
                                Button("Keep local draft") {
                                    resolve(recipe, as: .keepLocal)
                                }
                                if (try? localStore.conflictServerRecipe(for: recipe.id)) != nil {
                                    Button("Keep server version") {
                                        resolve(recipe, as: .keepServer)
                            }
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
            .sheet(item: $shareCardRecipe) { recipe in
                NavigationStack {
                    RecipeShareCardEditorView(recipe: recipe)
                }
            }
            .sheet(isPresented: $showingLocalFilters) {
                LocalRecipeFilterView(
                    cameras: localCameraOptions,
                    cameraID: selectedLocalCameraID,
                    evidence: selectedLocalEvidence,
                    filmSimulation: selectedLocalFilmSimulation,
                    filmSimulations: localFilmSimulationOptions,
                    categories: localCategoryOptions,
                    selectedCategories: selectedLocalCategories,
                    tagFilter: localTagFilterText,
                    context: RecipeExampleContextFilter(
                        subjects: selectedLocalSubjects.sorted(),
                        lighting: selectedLocalLighting.sorted(),
                        looks: selectedLocalLooks.sorted()
                    ),
                    onApply: { cameraID, evidence, filmSimulation, categories, tags, context in
                        selectedLocalCameraID = cameraID
                        selectedLocalEvidence = evidence
                        selectedLocalFilmSimulation = filmSimulation
                        selectedLocalCategories = categories
                        localTagFilterText = tags
                        selectedLocalSubjects = Set(context.subjects)
                        selectedLocalLighting = Set(context.lighting)
                        selectedLocalLooks = Set(context.looks)
                    }
                )
            }
            .sheet(isPresented: $showingCameraKit) {
                NavigationStack {
                    CameraKitCollectionPickerView(
                        collections: profileService.collections,
                        localStore: localStore,
                        cameraService: cameraService,
                        capabilityService: CameraCapabilityService(apiClient: apiClient)
                    )
                }
            }
            .fullScreenCover(isPresented: $showingDarkroom) {
                PhotoDarkroomView(
                    recipes: recipes,
                    loadCapabilities: { cameraID in try await darkroomCapabilities(for: cameraID) }
                )
            }
            .toolbar {
                ToolbarItemGroup(placement: .topBarLeading) {
                    Button {
                        showingDarkroom = true
                    } label: {
                        Label("JPEG Darkroom", systemImage: "slider.horizontal.3")
                    }
                    if authService.session != nil {
                        Button {
                            Task {
                                try? await profileService.loadCollections()
                                showingCameraKit = true
                            }
                        } label: {
                            Label("Install camera kit", systemImage: "square.stack.3d.up")
                        }
                        Button {
                            showingImporter = true
                        } label: {
                            Label("Import recipe", systemImage: "square.and.arrow.down")
                        }
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showingLocalFilters = true
                    } label: {
                        Label("Filter saved recipes", systemImage: "line.3.horizontal.decrease.circle")
                    }
                    if authService.session != nil {
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
            .alert("Library", isPresented: Binding(
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
        CameraTransferView(
            recipe: recipe,
            cameraService: cameraService,
            capabilityService: CameraCapabilityService(apiClient: apiClient)
        )
    }

    private func darkroomCapabilities(for cameraID: String) async throws -> [CameraCapabilityTransport] {
        let client: any APIClient
        if let session = authService.session {
            client = BearerAPIClient(apiClient: apiClient, accessToken: session.token)
        } else {
            client = apiClient
        }
        return try await CameraCapabilityService(apiClient: client).capabilities(for: cameraID)
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
            let state = syncState(for: recipe)
            Label(state.title, systemImage: state.systemImage)
                .font(.caption2)
                .foregroundStyle(state == .failed || state == .conflict ? .orange : .secondary)
        }
    }

    private func syncAndReload() async {
        reloadRecipes()
        guard let session = authService.session else { return }

        let authenticatedClient = BearerAPIClient(apiClient: apiClient, accessToken: session.token)
        let repository = RecipeRepository(apiClient: authenticatedClient, localStore: localStore)
        do {
            _ = try await repository.refreshRecipes()
        } catch {
            for recipe in recipes {
                try? localStore.markSyncState(.failed, for: recipe.id, error: error.localizedDescription)
            }
            message = "Sync failed. Retry individual recipes from their context menu."
        }
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

    private func syncState(for recipe: RecipeTransport) -> RecipeSyncState {
        (try? localStore.syncState(for: recipe.id)) ?? .synced
    }

    private func retry(_ recipe: RecipeTransport) async {
        guard let session = authService.session else { return }
        let repository = RecipeRepository(
            apiClient: BearerAPIClient(apiClient: apiClient, accessToken: session.token),
            localStore: localStore
        )
        do {
            _ = try await repository.retryRecipe(id: recipe.id)
            reloadRecipes()
        } catch {
            message = "Retry failed: \(error.localizedDescription)"
            reloadRecipes()
        }
    }

    private func resolve(_ recipe: RecipeTransport, as resolution: RecipeConflictResolution) {
        do {
            try localStore.resolveConflict(id: recipe.id, resolution: resolution)
            reloadRecipes()
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

private struct LocalCameraFilterOption: Identifiable {
    let id: String
    let name: String
}

private struct LocalRecipeFilterView: View {
    @Environment(\.dismiss) private var dismiss
    let cameras: [LocalCameraFilterOption]
    let filmSimulations: [String]
    let categories: [String]
    let onApply: (String?, CompatibilityEvidenceFilter, String?, Set<String>, String, RecipeExampleContextFilter) -> Void
    @State private var cameraID: String?
    @State private var evidence: CompatibilityEvidenceFilter
    @State private var filmSimulation: String?
    @State private var selectedCategories: Set<String>
    @State private var tagFilter: String
    @State private var subjects: Set<String>
    @State private var lighting: Set<String>
    @State private var looks: Set<String>

    init(
        cameras: [LocalCameraFilterOption],
        cameraID: String?,
        evidence: CompatibilityEvidenceFilter,
        filmSimulation: String?,
        filmSimulations: [String],
        categories: [String],
        selectedCategories: Set<String>,
        tagFilter: String,
        context: RecipeExampleContextFilter,
        onApply: @escaping (String?, CompatibilityEvidenceFilter, String?, Set<String>, String, RecipeExampleContextFilter) -> Void
    ) {
        self.cameras = cameras
        self.filmSimulations = filmSimulations
        self.categories = categories
        self.onApply = onApply
        _cameraID = State(initialValue: cameraID)
        _evidence = State(initialValue: evidence)
        _filmSimulation = State(initialValue: filmSimulation)
        _selectedCategories = State(initialValue: selectedCategories)
        _tagFilter = State(initialValue: tagFilter)
        _subjects = State(initialValue: Set(context.subjects))
        _lighting = State(initialValue: Set(context.lighting))
        _looks = State(initialValue: Set(context.looks))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Saved recipes") {
                    Picker("Camera model", selection: $cameraID) {
                        Text("Any camera").tag(nil as String?)
                        ForEach(cameras) { camera in
                            Text(camera.name).tag(Optional(camera.id))
                        }
                    }
                    Picker("Compatibility evidence", selection: $evidence) {
                        ForEach(CompatibilityEvidenceFilter.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .disabled(cameraID == nil)
                    if evidence != .any, cameraID != nil {
                        Text("Evidence filtering uses camera capability data cached on this iPhone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Picker("Film simulation", selection: $filmSimulation) {
                        Text("Any simulation").tag(nil as String?)
                        ForEach(filmSimulations, id: \.self) { value in
                            Text(value).tag(Optional(value))
                        }
                    }
                    TextField("Tags (comma-separated)", text: $tagFilter)
                        .textInputAutocapitalization(.never)
                }
                Section("Categories") {
                    ForEach(categories, id: \.self) { category in
                        Toggle(category, isOn: Binding(
                            get: { selectedCategories.contains(category) },
                            set: { isSelected in
                                if isSelected {
                                    selectedCategories.insert(category)
                                } else {
                                    selectedCategories.remove(category)
                                }
                            }
                        ))
                    }
                }
                Section("Example context") {
                    contextOptions("Subject", options: RecipeExampleContextOptions.subjects, selected: $subjects)
                    contextOptions("Lighting", options: RecipeExampleContextOptions.lighting, selected: $lighting)
                    contextOptions("Look", options: RecipeExampleContextOptions.looks, selected: $looks)
                    Text("Filters use labels saved with recipe examples and work without a network connection.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Saved recipe filters")
            .onChange(of: cameraID) {
                if cameraID == nil { evidence = .any }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Reset") {
                        cameraID = nil
                        evidence = .any
                        filmSimulation = nil
                        selectedCategories = []
                        tagFilter = ""
                        subjects = []
                        lighting = []
                        looks = []
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        onApply(cameraID, evidence, filmSimulation, selectedCategories, tagFilter, RecipeExampleContextFilter(
                            subjects: subjects.sorted(),
                            lighting: lighting.sorted(),
                            looks: looks.sorted()
                        ))
                        dismiss()
                    }
                }
            }
        }
    }

    private func contextOptions(
        _ title: String,
        options: [RecipeContextTag],
        selected: Binding<Set<String>>
    ) -> some View {
        DisclosureGroup(title) {
            ForEach(options) { option in
                Toggle(option.title, isOn: Binding(
                    get: { selected.wrappedValue.contains(option.id) },
                    set: { isSelected in
                        if isSelected {
                            selected.wrappedValue.insert(option.id)
                        } else {
                            selected.wrappedValue.remove(option.id)
                        }
                    }
                ))
            }
        }
    }
}
