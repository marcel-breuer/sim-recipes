import Foundation
import SwiftData

@Model
final class StoredRecipe {
    @Attribute(.unique) var id: String
    var name: String
    var recipeDescription: String?
    var styleRecommendation: String?
    var cameraModelID: String
    var lens: String?
    var categoriesData: Data
    var tagsData: Data
    var isPublished: Bool
    var sourceRecipeID: String?
    var sourceAuthorID: String?
    var updatedAt: Date
    var settingsData: Data
    var imagesData: Data = Data()
    var syncStateRawValue: String
    var lastSyncedAt: Date?
    var lastSyncError: String?
    var conflictRecipeData: Data?

    init(
        recipe: RecipeTransport,
        syncState: RecipeSyncState = .synced,
        syncedAt: Date? = Date(),
        encoder: JSONEncoder = JSONEncoder()
    ) throws {
        self.id = recipe.id
        self.name = recipe.name
        self.recipeDescription = recipe.description
        self.styleRecommendation = recipe.styleRecommendation
        self.cameraModelID = recipe.cameraModelID
        self.lens = recipe.lens
        self.categoriesData = try encoder.encode(recipe.categories)
        self.tagsData = try encoder.encode(recipe.tags)
        self.isPublished = recipe.isPublished
        self.sourceRecipeID = recipe.provenance?.sourceRecipeID
        self.sourceAuthorID = recipe.provenance?.sourceAuthorID
        self.updatedAt = recipe.updatedAt
        self.settingsData = try encoder.encode(recipe.settings)
        self.imagesData = try encoder.encode(recipe.images)
        self.syncStateRawValue = syncState.rawValue
        self.lastSyncedAt = syncedAt
        self.lastSyncError = nil
        self.conflictRecipeData = nil
    }

    var syncState: RecipeSyncState {
        get { RecipeSyncState(rawValue: syncStateRawValue) ?? .conflict }
        set { syncStateRawValue = newValue.rawValue }
    }

    func transport(decoder: JSONDecoder = JSONDecoder()) throws -> RecipeTransport {
        let provenance: RecipeProvenanceTransport?
        if sourceRecipeID != nil || sourceAuthorID != nil {
            provenance = RecipeProvenanceTransport(
                sourceRecipeID: sourceRecipeID,
                sourceAuthorID: sourceAuthorID
            )
        } else {
            provenance = nil
        }

        return RecipeTransport(
            id: id,
            name: name,
            description: recipeDescription,
            styleRecommendation: styleRecommendation,
            cameraModelID: cameraModelID,
            lens: lens,
            categories: try decoder.decode([String].self, from: categoriesData),
            tags: try decoder.decode([String].self, from: tagsData),
            isPublished: isPublished,
            provenance: provenance,
            updatedAt: updatedAt,
            settings: try decoder.decode([RecipeSettingTransport].self, from: settingsData),
            images: (try? decoder.decode([RecipeImageTransport].self, from: imagesData)) ?? []
        )
    }
}
