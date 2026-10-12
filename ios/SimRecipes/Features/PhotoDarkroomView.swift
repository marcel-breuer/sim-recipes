import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct PhotoDarkroomView: View {
    let recipes: [RecipeTransport]
    let loadCapabilities: (String) async throws -> [CameraCapabilityTransport]

    @Environment(\.dismiss) private var dismiss
    @State private var projects: [PhotoDarkroomProject] = []
    @State private var currentProjectID: UUID?
    @State private var syncProjectIDs: Set<UUID> = []
    @State private var photoItems: [PhotosPickerItem] = []
    @State private var showingFileImporter = false
    @State private var showingSyncSheet = false
    @State private var preserveMetadata = false
    @State private var isLoading = false
    @State private var isExporting = false
    @State private var preview: PhotoDarkroomPreview?
    @State private var exportDocument: PhotoDarkroomJPEGDocument?
    @State private var showingExporter = false
    @State private var exportTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var persistenceTask: Task<Void, Never>?

    private let store = PhotoDarkroomStore()
    private let renderer = PhotoDarkroomRenderer()

    private var currentProject: PhotoDarkroomProject? {
        projects.first(where: { $0.id == currentProjectID })
    }

    private var syncTargetCount: Int {
        syncProjectIDs.filter { $0 != currentProjectID }.count
    }

    var body: some View {
        NavigationStack {
            Group {
                if projects.isEmpty {
                    ContentUnavailableView {
                        Label("JPEG Darkroom", systemImage: "slider.horizontal.3")
                    } description: {
                        Text("Edit photos locally. Originals stay unchanged, and exports are separate JPEG copies.")
                    } actions: {
                        importActions
                    }
                } else {
                    editor
                }
            }
            .navigationTitle("Darkroom")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !projects.isEmpty {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        importActions
                        Button {
                            showingSyncSheet = true
                        } label: {
                            Label("Sync selected edits", systemImage: "square.stack.3d.up")
                        }
                        .disabled(syncTargetCount == 0 || currentProject == nil)
                        Button {
                            beginExport()
                        } label: {
                            Label("Export JPEG", systemImage: "square.and.arrow.up")
                        }
                        .disabled(currentProject == nil || isExporting)
                    }
                }
            }
            .task { await loadProjects() }
            .task(id: previewRequest) { await renderCurrentPreview() }
            .onDisappear {
                persistenceTask?.cancel()
                exportTask?.cancel()
            }
            .onChange(of: photoItems) {
                let selected = photoItems
                photoItems = []
                Task { await importPhotos(selected) }
            }
            .fileImporter(
                isPresented: $showingFileImporter,
                allowedContentTypes: [.jpeg],
                allowsMultipleSelection: true
            ) { result in
                Task { await importFiles(result) }
            }
            .fileExporter(
                isPresented: $showingExporter,
                document: exportDocument,
                contentType: .jpeg,
                defaultFilename: exportDocument?.fileURL.deletingPathExtension().lastPathComponent ?? "edited-photo"
            ) { result in
                if case let .failure(error) = result { errorMessage = error.localizedDescription }
                if let url = exportDocument?.fileURL { try? FileManager.default.removeItem(at: url) }
                exportDocument = nil
            }
            .sheet(isPresented: $showingSyncSheet) {
                PhotoDarkroomSyncSheet(
                    selectedCount: syncTargetCount,
                    onApply: applySync
                )
            }
            .alert("JPEG Darkroom", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
        }
    }

    private var importActions: some View {
        Menu {
            PhotosPicker(selection: $photoItems, maxSelectionCount: 30, matching: .images) {
                Label("Photo Library", systemImage: "photo")
            }
            Button {
                showingFileImporter = true
            } label: {
                Label("Browse JPEG Files", systemImage: "folder")
            }
        } label: {
            Label("Add photos", systemImage: "plus")
        }
        .disabled(isLoading)
    }

    private var editor: some View {
        Form {
            Section("Photos · \(projects.count)") {
                ForEach(projects) { project in
                    HStack(spacing: 12) {
                        Button {
                            currentProjectID = project.id
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: currentProjectID == project.id ? "photo.fill" : "photo")
                                    .foregroundStyle(currentProjectID == project.id ? Color.accentColor : Color.secondary)
                                VStack(alignment: .leading) {
                                    Text(project.displayName).lineLimit(1)
                                    Text(project.edits.recipeName ?? "Original")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        Toggle("Include in sync", isOn: syncBinding(for: project.id))
                            .labelsHidden()
                            .accessibilityLabel("Include \(project.displayName) in batch edit sync")
                    }
                    .contentShape(Rectangle())
                    .onChange(of: project) { _, changedProject in persist(changedProject) }
                    .contextMenu {
                        Button("Remove from Darkroom", systemImage: "trash", role: .destructive) {
                            Task { await remove(project) }
                        }
                    }
                }
            }

            if let project = currentProject {
                Section("Before and after") {
                    if isLoading {
                        ProgressView("Preparing photo…").frame(maxWidth: .infinity, minHeight: 180)
                    } else if let preview,
                              let before = UIImage(data: preview.originalJPEG),
                              let after = UIImage(data: preview.editedJPEG) {
                        RecipeBeforeAfterView(originalImage: before, previewImage: after)
                            .frame(height: 300)
                    } else {
                        Label("The JPEG preview is unavailable.", systemImage: "photo.badge.exclamationmark")
                    }
                    Text("Recipe rendering is an approximation and does not reproduce Fujifilm color science exactly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Previews are optimized for responsiveness; exports retain up to 5,000 pixels on the long edge.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if let preview, !preview.unsupportedRecipeSettings.isEmpty {
                        Text("Camera does not support: \(preview.unsupportedRecipeSettings.joined(separator: ", ")).")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                    if let preview, !preview.notSimulatedRecipeSettings.isEmpty {
                        Text("This preview does not approximate: \(preview.notSimulatedRecipeSettings.joined(separator: ", ")).")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Recipe") {
                    Picker("Apply recipe", selection: recipeBinding(for: project)) {
                        Text("No recipe").tag("")
                        ForEach(recipes) { recipe in
                            Text(recipe.name).tag(recipe.id)
                        }
                    }
                    Text(project.edits.recipeName.map { "Approximate look: \($0)" } ?? "Choose a locally saved recipe.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Light and color") {
                    adjustmentSlider("Exposure", value: editBinding(for: project, keyPath: \.exposure), range: -2...2)
                    adjustmentSlider("Contrast", value: editBinding(for: project, keyPath: \.contrast), range: -0.5...0.5)
                    adjustmentSlider("Saturation", value: editBinding(for: project, keyPath: \.saturation), range: -1...1)
                    adjustmentSlider("Temperature", value: editBinding(for: project, keyPath: \.temperature), range: -50...50)
                    adjustmentSlider("Tint", value: editBinding(for: project, keyPath: \.tint), range: -50...50)
                }

                Section("Crop and straighten") {
                    adjustmentSlider("Crop", value: editBinding(for: project, keyPath: \.cropScale), range: 1...2.5)
                    adjustmentSlider("Crop horizontal", value: editBinding(for: project, keyPath: \.cropOffsetX), range: -0.5...0.5)
                    adjustmentSlider("Crop vertical", value: editBinding(for: project, keyPath: \.cropOffsetY), range: -0.5...0.5)
                    adjustmentSlider("Straighten", value: editBinding(for: project, keyPath: \.straightenDegrees), range: -15...15)
                    Picker("Frame", selection: frameBinding(for: project)) {
                        Text("None").tag(PhotoDarkroomFrame.none)
                        Text("White").tag(PhotoDarkroomFrame.white)
                        Text("Black").tag(PhotoDarkroomFrame.black)
                    }
                }

                Section("Export privacy") {
                    Toggle("Keep original metadata, including GPS", isOn: $preserveMetadata)
                    Text(preserveMetadata
                         ? "The exported copy preserves the source JPEG metadata and location data."
                         : "The exported copy removes EXIF, GPS, and other source metadata.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if isExporting {
                        ProgressView("Rendering JPEG…")
                        Button("Cancel export", role: .cancel) { exportTask?.cancel() }
                    } else {
                        Button {
                            beginExport()
                        } label: {
                            Label("Export a separate JPEG copy", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
    }

    private var previewRequest: PreviewRequest? {
        currentProject.map { PreviewRequest(id: $0.id, edits: $0.edits) }
    }

    private func loadProjects() async {
        do {
            projects = try await store.load()
            currentProjectID = projects.first?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isLoading = true
        defer { isLoading = false }
        var rejectedCount = 0
        for item in items {
            guard item.supportedContentTypes.contains(.jpeg) else {
                rejectedCount += 1
                continue
            }
            do {
                if let bytes = try await item.loadTransferable(type: Data.self) {
                    await importJPEG(bytes, filename: "photo-\(projects.count + 1).jpg")
                }
            } catch {
                rejectedCount += 1
            }
        }
        if rejectedCount > 0 { errorMessage = "Skipped \(rejectedCount) unreadable or non-JPEG photo\(rejectedCount == 1 ? "" : "s")." }
    }

    private func importJPEG(_ bytes: Data, filename: String) async {
        do {
            let result = try await store.importJPEG(bytes, filename: filename)
            if !result.wasDuplicate { projects.append(result.project) }
            currentProjectID = result.project.id
            syncProjectIDs.insert(result.project.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importFiles(_ result: Result<[URL], Error>) async {
        isLoading = true
        defer { isLoading = false }
        do {
            let urls = try result.get()
            var rejectedCount = 0
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                guard UTType(filenameExtension: url.pathExtension)?.conforms(to: .jpeg) == true else {
                    rejectedCount += 1
                    continue
                }
                do {
                    let bytes = try Data(contentsOf: url, options: .mappedIfSafe)
                    await importJPEG(bytes, filename: url.lastPathComponent)
                } catch {
                    rejectedCount += 1
                }
            }
            if rejectedCount > 0 { errorMessage = "Skipped \(rejectedCount) unreadable or non-JPEG file\(rejectedCount == 1 ? "" : "s")." }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renderCurrentPreview() async {
        guard let project = currentProject else { preview = nil; return }
        isLoading = true
        defer { isLoading = false }
        do {
            let sourceURL = await store.sourceURL(for: project)
            preview = try await renderer.preview(sourceURL: sourceURL, edits: project.edits)
        } catch is CancellationError {
            return
        } catch {
            preview = nil
            errorMessage = error.localizedDescription
        }
    }

    private func applyRecipe(_ recipeID: String, to project: PhotoDarkroomProject) async {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        if recipeID.isEmpty {
            projects[index].edits.recipeID = nil
            projects[index].edits.recipeName = nil
            projects[index].edits.recipeSettings = []
            projects[index].edits.capabilities = []
            return
        }
        guard let recipe = recipes.first(where: { $0.id == recipeID }) else { return }
        do {
            let capabilities = try await loadCapabilities(recipe.cameraModelID)
            projects[index].edits.recipeID = recipe.id
            projects[index].edits.recipeName = recipe.name
            projects[index].edits.recipeSettings = recipe.settings
            projects[index].edits.capabilities = capabilities
        } catch {
            errorMessage = "Recipe capability data could not be loaded. Connect once to validate the recipe before using it in the darkroom."
        }
    }

    private func applySync(_ selection: Set<PhotoDarkroomSyncSelection>) {
        guard let source = currentProject else { return }
        for index in projects.indices where syncProjectIDs.contains(projects[index].id) && projects[index].id != source.id {
            projects[index].edits = PhotoDarkroomBatchSync.apply(
                source: source.edits, to: projects[index].edits, selection: selection
            )
        }
        showingSyncSheet = false
    }

    private func remove(_ project: PhotoDarkroomProject) async {
        do {
            persistenceTask?.cancel()
            try await store.delete(project)
            projects.removeAll { $0.id == project.id }
            syncProjectIDs.remove(project.id)
            if currentProjectID == project.id {
                currentProjectID = projects.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func exportCurrent() async {
        guard let project = currentProject else { return }
        isExporting = true
        defer {
            isExporting = false
            exportTask = nil
        }
        do {
            let sourceURL = await store.sourceURL(for: project)
            let url = try await renderer.export(sourceURL: sourceURL, edits: project.edits, preservingMetadata: preserveMetadata)
            exportDocument = PhotoDarkroomJPEGDocument(fileURL: url)
            showingExporter = true
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginExport() {
        guard !isExporting else { return }
        exportTask = Task { await exportCurrent() }
    }

    private func persist(_ project: PhotoDarkroomProject) {
        persistenceTask?.cancel()
        persistenceTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do { try await store.update(project) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    private func syncBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { syncProjectIDs.contains(id) },
            set: { selected in
                if selected { syncProjectIDs.insert(id) }
                else { syncProjectIDs.remove(id) }
            }
        )
    }

    private func recipeBinding(for project: PhotoDarkroomProject) -> Binding<String> {
        Binding(
            get: { project.edits.recipeID ?? "" },
            set: { id in Task { await applyRecipe(id, to: project) } }
        )
    }

    private func editBinding(
        for project: PhotoDarkroomProject,
        keyPath: WritableKeyPath<PhotoDarkroomEdits, Double>
    ) -> Binding<Double> {
        Binding(
            get: { project.edits[keyPath: keyPath] },
            set: { value in
                guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
                projects[index].edits[keyPath: keyPath] = value
            }
        )
    }

    private func frameBinding(for project: PhotoDarkroomProject) -> Binding<PhotoDarkroomFrame> {
        Binding(
            get: { project.edits.frame },
            set: { value in
                guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
                projects[index].edits.frame = value
            }
        )
    }

    private func adjustmentSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(1)))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
                .accessibilityLabel(title)
        }
    }
}

private struct PreviewRequest: Equatable {
    let id: UUID
    let edits: PhotoDarkroomEdits
}

private struct PhotoDarkroomSyncSheet: View {
    let selectedCount: Int
    let onApply: (Set<PhotoDarkroomSyncSelection>) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var syncRecipe = true
    @State private var syncLightColor = true
    @State private var syncCrop = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Selected photos") {
                    Text("Apply selected adjustments from the current photo to \(selectedCount) selected photo\(selectedCount == 1 ? "" : "s").")
                }
                Section("Adjustments to sync") {
                    Toggle("Recipe approximation", isOn: $syncRecipe)
                    Toggle("Light, color, and frame", isOn: $syncLightColor)
                    Toggle("Crop and straighten", isOn: $syncCrop)
                }
            }
            .navigationTitle("Sync Edits")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        var selection: Set<PhotoDarkroomSyncSelection> = []
                        if syncRecipe { selection.insert(.recipe) }
                        if syncLightColor { selection.insert(.lightAndColor) }
                        if syncCrop { selection.insert(.cropAndStraighten) }
                        onApply(selection)
                    }
                    .disabled(!syncRecipe && !syncLightColor && !syncCrop)
                }
            }
        }
    }
}

