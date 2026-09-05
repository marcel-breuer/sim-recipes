import Foundation
import SwiftData

enum RecipeStoreMergeResult: Equatable {
    case inserted
    case updated
    case conflict
}

enum RecipeStoreError: LocalizedError, Equatable {
    case publishedRecipeIsImmutable

    var errorDescription: String? {
        "Published recipes are immutable. Create a copy to make changes."
    }
}

@MainActor
final class LocalRecipeStore {
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        self.modelContainer = try ModelContainer(
            for: StoredRecipe.self,
            configurations: configuration
        )
        self.modelContext = ModelContext(modelContainer)
    }

    func upsert(_ recipe: RecipeTransport, syncedAt: Date = Date()) throws {
        _ = try mergeRemote(recipe, syncedAt: syncedAt)
    }

    func mergeRemote(
        _ recipe: RecipeTransport,
        syncedAt: Date = Date()
    ) throws -> RecipeStoreMergeResult {
        let existing = try modelContext.fetch(FetchDescriptor<StoredRecipe>())
            .first(where: { $0.id == recipe.id })

        if let existing {
            if [.localOnly, .pendingUpload].contains(existing.syncState) && !existing.isPublished {
                existing.syncState = .conflict
                try modelContext.save()
                return .conflict
            }

            existing.name = recipe.name
            existing.recipeDescription = recipe.description
            existing.styleRecommendation = recipe.styleRecommendation
            existing.cameraModelID = recipe.cameraModelID
            existing.lens = recipe.lens
            existing.categoriesData = try JSONEncoder().encode(recipe.categories)
            existing.tagsData = try JSONEncoder().encode(recipe.tags)
            existing.isPublished = recipe.isPublished
            existing.sourceRecipeID = recipe.provenance?.sourceRecipeID
            existing.sourceAuthorID = recipe.provenance?.sourceAuthorID
            existing.updatedAt = recipe.updatedAt
            existing.settingsData = try JSONEncoder().encode(recipe.settings)
            existing.syncState = .synced
            existing.lastSyncedAt = syncedAt
        } else {
            modelContext.insert(try StoredRecipe(recipe: recipe, syncedAt: syncedAt))
        }

        try modelContext.save()
        return existing == nil ? .inserted : .updated
    }

    func saveLocally(_ recipe: RecipeTransport) throws {
        let existing = try modelContext.fetch(FetchDescriptor<StoredRecipe>())
            .first(where: { $0.id == recipe.id })

        if let existing {
            guard !existing.isPublished else {
                throw RecipeStoreError.publishedRecipeIsImmutable
            }

            existing.name = recipe.name
            existing.recipeDescription = recipe.description
            existing.styleRecommendation = recipe.styleRecommendation
            existing.cameraModelID = recipe.cameraModelID
            existing.lens = recipe.lens
            existing.categoriesData = try JSONEncoder().encode(recipe.categories)
            existing.tagsData = try JSONEncoder().encode(recipe.tags)
            existing.isPublished = recipe.isPublished
            existing.sourceRecipeID = recipe.provenance?.sourceRecipeID
            existing.sourceAuthorID = recipe.provenance?.sourceAuthorID
            existing.updatedAt = recipe.updatedAt
            existing.settingsData = try JSONEncoder().encode(recipe.settings)
            existing.syncState = .pendingUpload
        } else {
            modelContext.insert(try StoredRecipe(recipe: recipe, syncState: .localOnly, syncedAt: nil))
        }

        try modelContext.save()
    }

    func syncState(for id: String) throws -> RecipeSyncState? {
        try modelContext.fetch(FetchDescriptor<StoredRecipe>())
            .first(where: { $0.id == id })?
            .syncState
    }

    func recipe(id: String) throws -> RecipeTransport? {
        let storedRecipe = try modelContext.fetch(FetchDescriptor<StoredRecipe>())
            .first(where: { $0.id == id })
        return try storedRecipe?.transport()
    }

    func recipes() throws -> [RecipeTransport] {
        let storedRecipes = try modelContext.fetch(FetchDescriptor<StoredRecipe>())
        return try storedRecipes
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { try $0.transport() }
    }
}
