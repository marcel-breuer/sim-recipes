import Foundation
import Combine
import PhotosUI

@MainActor
final class RecipeEditorViewModel: ObservableObject {
    @Published private(set) var cameras: [CameraModelTransport] = []
    @Published private(set) var categories: [CategoryTransport] = []
    @Published private(set) var capabilities: [CameraCapabilityTransport] = []
    @Published var draft: RecipeDraft
    @Published private(set) var isLoading = false
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private let repository: RecipeRepository
    private let capabilityService: CameraCapabilityService
    private let draftStore: RecipeDraftStore

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

    func addPhotos(_ items: [PhotosPickerItem]) async {
        let remaining = max(0, 5 - draft.totalImageCount)
        guard remaining > 0 else {
            errorMessage = RecipeDraftValidationError.tooManyImages.localizedDescription
            return
        }

        for item in items.prefix(remaining) {
            do {
                guard let data = try await item.loadTransferable(type: Data.self) else { continue }
                draft.images.append(
                    RecipeDraftImage(
                        filename: "recipe-\(draft.images.count + 1).jpg",
                        data: data
                    )
                )
            } catch {
                errorMessage = "The selected image could not be loaded."
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
        do {
            try validate(requireImage: true)
            isSaving = true
            defer { isSaving = false }
            let categoryIDs = categories.filter { draft.categories.contains($0.name) }.map(\.id)
            let recipe: RecipeTransport
            if draft.id == nil {
                recipe = try await repository.create(draft, categoryIDs: categoryIDs)
            } else {
                recipe = try await repository.update(draft, categoryIDs: categoryIDs)
            }
            draft = RecipeDraft(recipe: recipe)
            try draftStore.save(draft)
            errorMessage = "Private recipe saved."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func publish() async {
        do {
            try validate(requireImage: true)
            isSaving = true
            defer { isSaving = false }
            let categoryIDs = categories.filter { draft.categories.contains($0.name) }.map(\.id)
            let recipe: RecipeTransport
            if draft.id == nil {
                recipe = try await repository.create(draft, categoryIDs: categoryIDs)
            } else {
                recipe = try await repository.update(draft, categoryIDs: categoryIDs)
            }
            let published = try await repository.publish(id: recipe.id)
            draft = RecipeDraft(recipe: published)
            try draftStore.delete(id: published.id)
        } catch {
            errorMessage = error.localizedDescription
        }
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
