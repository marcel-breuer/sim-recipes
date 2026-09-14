import Foundation
import Combine

enum RecipeUploadState: Equatable {
    case idle
    case preparing
    case uploading(progress: Double)
    case succeeded
    case failed(message: String)
}

@MainActor
final class RecipeEditorViewModel: ObservableObject {
    @Published private(set) var cameras: [SupportedCameraTransport] = []
    @Published private(set) var categories: [CategoryTransport] = []
    @Published private(set) var capabilities: [CameraCapabilityTransport] = []
    @Published var draft: RecipeDraft
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published private(set) var uploadState: RecipeUploadState = .idle
    @Published var errorMessage: String?

    private let repository: RecipeRepository
    private let capabilityService: CameraCapabilityService
    private let draftStore: RecipeDraftStore
    private var activeUploadTask: Task<Void, Never>?
    private var lastUploadAction: UploadAction?

    private enum UploadAction: Equatable {
        case save
        case publish
    }

    init(
        draft: RecipeDraft = RecipeDraft(),
        repository: RecipeRepository,
        capabilityService: CameraCapabilityService,
        draftStore: RecipeDraftStore = RecipeDraftStore()
    ) {
        self.draft = draft
        self.repository = repository
        self.capabilityService = capabilityService
        self.draftStore = draftStore
    }

    var canEdit: Bool {
        !draft.isPublished
    }

    func load() async {
        guard cameras.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            async let loadedCameras = capabilityService.supportedCameras()
            async let loadedCategories = capabilityService.categories()
            cameras = try await loadedCameras
            categories = try await loadedCategories

            if draft.cameraModelID.isEmpty {
                draft.cameraModelID = cameras.first?.id ?? ""
            }
            try await loadCapabilities()
            fillMissingSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cameraDidChange() async {
        do {
            draft.settings = []
            try await loadCapabilities()
            fillMissingSettings()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func addPhotos(_ images: [Data]) {
        let remaining = max(0, 5 - draft.totalImageCount)
        guard remaining > 0 else {
            errorMessage = RecipeDraftValidationError.tooManyImages.localizedDescription
            return
        }

        for data in images.prefix(remaining) {
            do {
                draft.images.append(try RecipeImagePreparer.prepare(
                    data,
                    filename: "recipe-\(draft.images.count + 1).jpg"
                ))
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func removePhoto(_ image: RecipeDraftImage) {
        draft.images.removeAll { $0.id == image.id }
    }

    func setSetting(_ value: JSONValue, for key: String) {
        if let index = draft.settings.firstIndex(where: { $0.key == key }) {
            draft.settings[index] = RecipeSettingTransport(key: key, value: value)
        } else {
            draft.settings.append(RecipeSettingTransport(key: key, value: value))
        }
    }

    func value(for key: String) -> JSONValue {
        draft.settings.first(where: { $0.key == key })?.value ?? .null
    }

    func saveDraftLocally() {
        do {
            try draftStore.save(draft)
            errorMessage = "Draft saved on this iPhone."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func save() async {
        await upload(.save)
    }

    func startSave() {
        startUpload(.save)
    }

    func startPublish() {
        startUpload(.publish)
    }

    func cancelUpload() {
        activeUploadTask?.cancel()
        activeUploadTask = nil
        isSaving = false
        uploadState = .idle
        errorMessage = "Upload cancelled."
    }

    func retryUpload() {
        guard let lastUploadAction else { return }
        startUpload(lastUploadAction)
    }

    var uploadProgress: Double {
        guard case let .uploading(progress) = uploadState else { return 0 }
        return progress
    }

    var isUploadInProgress: Bool {
        switch uploadState {
        case .preparing, .uploading:
            true
        case .idle, .succeeded, .failed:
            false
        }
    }

    var canRetryUpload: Bool {
        if case .failed = uploadState { return lastUploadAction != nil }
        return false
    }

    private func startUpload(_ action: UploadAction) {
        activeUploadTask?.cancel()
        lastUploadAction = action
        activeUploadTask = Task { [weak self] in
            await self?.upload(action)
        }
    }

    private func upload(_ action: UploadAction) async {
        do {
            try validate(requireImage: true)
            isSaving = true
            defer { isSaving = false }
            uploadState = .preparing
            let categoryIDs = categories.filter { draft.categories.contains($0.name) }.map(\.id)
            let recipe: RecipeTransport
            let progress: APIUploadProgressHandler = { [weak self] value in
                Task { @MainActor [weak self] in
                    guard let self, self.isSaving else { return }
                    self.uploadState = .uploading(progress: value)
                }
            }
            if draft.id == nil {
                recipe = try await repository.create(draft, categoryIDs: categoryIDs, progress: progress)
            } else {
                recipe = try await repository.update(draft, categoryIDs: categoryIDs, progress: progress)
            }
            if action == .publish {
                let published = try await repository.publish(id: recipe.id)
                draft = RecipeDraft(recipe: published)
                try draftStore.delete(id: published.id)
            } else {
                draft = RecipeDraft(recipe: recipe)
                try draftStore.save(draft)
            }
            uploadState = .succeeded
            errorMessage = action == .publish ? "Recipe published." : "Private recipe saved."
        } catch is CancellationError {
            uploadState = .idle
            errorMessage = "Upload cancelled."
        } catch {
            uploadState = .failed(message: error.localizedDescription)
            errorMessage = error.localizedDescription
        }
    }

    func publish() async {
        await upload(.publish)
    }

    private func validate(requireImage: Bool) throws {
        guard canEdit else { throw RecipeDraftValidationError.publishedRecipeIsImmutable }
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeDraftValidationError.nameRequired
        }
        guard !draft.cameraModelID.isEmpty else { throw RecipeDraftValidationError.cameraRequired }
        guard draft.totalImageCount <= 5 else { throw RecipeDraftValidationError.tooManyImages }
        if requireImage, draft.totalImageCount == 0 {
            throw RecipeDraftValidationError.imageRequired
        }
    }

    private func loadCapabilities() async throws {
        guard !draft.cameraModelID.isEmpty else {
            capabilities = []
            return
        }
        capabilities = try await capabilityService.capabilities(for: draft.cameraModelID)
    }

    private func fillMissingSettings() {
        for capability in capabilities where !draft.settings.contains(where: { $0.key == capability.key }) {
            setSetting(defaultValue(for: capability), for: capability.key)
        }
    }

    private func defaultValue(for capability: CameraCapabilityTransport) -> JSONValue {
        switch capability.valueType {
        case "enum":
            if case let .array(values) = capability.allowedValues,
               let first = values.first {
                return first
            }
            return .string("")
        case "integer":
            return .number(capability.minimum ?? 0)
        case "decimal":
            return .number(capability.minimum ?? 0)
        case "boolean":
            return .boolean(false)
        case "object":
            guard case let .object(values) = capability.allowedValues else { return .object([:]) }
            var result: [String: JSONValue] = [:]
            if case let .array(axes) = values["axes"] {
                for axis in axes.compactMap(\.stringValue) {
                    result[axis] = .number(capability.minimum ?? 0)
                }
            } else {
                for (key, value) in values {
                    if case let .array(options) = value, let first = options.first {
                        result[key] = first
                    } else {
                        result[key] = .number(capability.minimum ?? 0)
                    }
                }
            }
            return .object(result)
        default:
            return .string("")
        }
    }
}
