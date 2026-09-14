import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let simRecipe = UTType(exportedAs: "dev.marcel-breuer.simrecipes.recipe")
}

struct SimRecipeFile: Codable, Equatable, Sendable {
    static let currentSchemaVersion = 1

    let schemaVersion: Int
    let recipe: SimRecipePayload
}

struct SimRecipePayload: Codable, Equatable, Sendable {
    let name: String
    let description: String?
    let recommendation: String?
    let cameraModelID: String
    let lens: String?
    let categories: [String]
    let tags: [String]
    let settings: [RecipeSettingTransport]
    let provenance: RecipeProvenanceTransport?

    enum CodingKeys: String, CodingKey {
        case name, description, recommendation
        case cameraModelID = "camera_model_id"
        case lens, categories, tags, settings, provenance
    }

    init(recipe: RecipeTransport) {
        name = recipe.name
        description = recipe.description
        recommendation = recipe.styleRecommendation
        cameraModelID = recipe.cameraModelID
        lens = recipe.lens
        categories = recipe.categories
        tags = recipe.tags
        settings = recipe.settings
        provenance = recipe.provenance
    }
}

enum RecipeImportError: LocalizedError, Equatable {
    case invalidJSON
    case unsupportedSchema(Int)
    case nameRequired
    case cameraUnsupported
    case duplicateSetting(String)
    case missingSetting(String)
    case invalidSetting(String)
    case unsupportedSettingValue(String)
    case invalidProvenance

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "The file is not a valid SimRecipes file."
        case let .unsupportedSchema(version):
            "This SimRecipes file uses unsupported schema version \(version)."
        case .nameRequired:
            "The imported recipe must have a name."
        case .cameraUnsupported:
            "The recipe targets a camera that is not supported on this device."
        case let .duplicateSetting(key):
            "The file contains the setting \"\(key)\" more than once."
        case let .missingSetting(key):
            "The camera does not support the setting \"\(key)\"."
        case let .invalidSetting(key):
            "The value for \"\(key)\" has the wrong type or shape."
        case let .unsupportedSettingValue(key):
            "The value for \"\(key)\" is outside the camera capability set."
        case .invalidProvenance:
            "The file contains incomplete provenance information."
        }
    }
}

enum RecipePortabilityService {
    static func exportData(recipe: RecipeTransport) throws -> Data {
        let file = SimRecipeFile(
            schemaVersion: SimRecipeFile.currentSchemaVersion,
            recipe: SimRecipePayload(recipe: recipe)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(file)
    }

    static func importDraft(
        from data: Data,
        supportedCameras: [SupportedCameraTransport]
    ) throws -> RecipeDraft {
        let file: SimRecipeFile
        do {
            file = try JSONDecoder().decode(SimRecipeFile.self, from: data)
        } catch {
            throw RecipeImportError.invalidJSON
        }

        guard file.schemaVersion == SimRecipeFile.currentSchemaVersion else {
            throw RecipeImportError.unsupportedSchema(file.schemaVersion)
        }
        let payload = file.recipe
        guard !payload.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RecipeImportError.nameRequired
        }
        guard let camera = supportedCameras.first(where: {
            $0.id == payload.cameraModelID || $0.slug == payload.cameraModelID
        }) else {
            throw RecipeImportError.cameraUnsupported
        }
        if let provenance = payload.provenance,
           (provenance.sourceRecipeID?.isEmpty == true || provenance.sourceAuthorID?.isEmpty == true) {
            throw RecipeImportError.invalidProvenance
        }

        try validate(settings: payload.settings, capabilities: camera.capabilities)

        var draft = RecipeDraft()
        draft.name = payload.name.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.description = payload.description ?? ""
        draft.recommendation = payload.recommendation ?? ""
        draft.cameraModelID = camera.id
        draft.lens = payload.lens ?? ""
        draft.categories = payload.categories
        draft.tags = payload.tags
        draft.settings = payload.settings
        return draft
    }

    private static func validate(
        settings: [RecipeSettingTransport],
        capabilities: [CameraCapabilityTransport]
    ) throws {
        let capabilitiesByKey = Dictionary(uniqueKeysWithValues: capabilities.map { ($0.key, $0) })
        var seenKeys = Set<String>()

        for setting in settings {
            guard seenKeys.insert(setting.key).inserted else {
                throw RecipeImportError.duplicateSetting(setting.key)
            }
            guard let capability = capabilitiesByKey[setting.key] else {
                throw RecipeImportError.missingSetting(setting.key)
            }
            guard matchesType(setting.value, capability: capability) else {
                throw RecipeImportError.invalidSetting(setting.key)
            }
            guard matchesAllowedValue(setting.value, capability: capability) else {
                throw RecipeImportError.unsupportedSettingValue(setting.key)
            }
        }
    }

    private static func matchesType(_ value: JSONValue, capability: CameraCapabilityTransport) -> Bool {
        switch capability.valueType {
        case "integer":
            value.numberValue.map { $0.rounded() == $0 } ?? false
        case "decimal", "number":
            value.numberValue != nil
        case "boolean":
            if case .boolean = value { true } else { false }
        case "object":
            if case .object = value { true } else { false }
        default:
            value.stringValue != nil
        }
    }

    private static func matchesAllowedValue(_ value: JSONValue, capability: CameraCapabilityTransport) -> Bool {
        if let minimum = capability.minimum,
           let number = value.numberValue,
           number < minimum {
            return false
        }
        if let maximum = capability.maximum,
           let number = value.numberValue,
           number > maximum {
            return false
        }
        guard let allowed = capability.allowedValues else { return true }
        if case let .array(options) = allowed {
            return options.contains(value) || options.contains { $0.stringValue == value.stringValue }
        }
        if case let (.object(valueObject), .object(allowedObject)) = (value, allowed) {
            for (key, allowedValue) in allowedObject where key != "axes" {
                if case let .array(options) = allowedValue,
                   let actual = valueObject[key],
                   !options.contains(actual) {
                    return false
                }
            }
        }
        return true
    }
}

struct SimRecipeFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.simRecipe] }
    static var writableContentTypes: [UTType] { [.simRecipe] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

enum RecipeShareLink {
    static let baseURL = URL(string: "https://simrecipes.marcel-breuer.dev/recipes")!

    static func url(for recipe: RecipeTransport) -> URL? {
        guard recipe.isPublished else { return nil }
        return baseURL.appendingPathComponent(recipe.id)
    }
}
