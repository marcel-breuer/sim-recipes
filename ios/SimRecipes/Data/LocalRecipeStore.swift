import Foundation
import SwiftData

enum RecipeStoreMergeResult: Equatable {
    case inserted
    case updated
    case conflict
}

enum RecipeStoreError: LocalizedError, Equatable {
    case publishedRecipeIsImmutable
    case conflictNotFound

    var errorDescription: String? {
        switch self {
        case .publishedRecipeIsImmutable:
            "Published recipes are immutable. Create a copy to make changes."
        case .conflictNotFound:
            "The sync conflict is no longer available. Refresh the library and try again."
        }
    }
}

enum RecipeConflictResolution: Sendable {
    case keepLocal
    case keepServer
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
            if !existing.isPublished && ![.synced, .conflict].contains(existing.syncState) {
                existing.syncState = .conflict
                existing.conflictRecipeData = try JSONEncoder().encode(recipe)
                existing.lastSyncError = "The server has a newer version of this draft."
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
            existing.imagesData = try JSONEncoder().encode(recipe.images)
            existing.syncState = .synced
            existing.lastSyncedAt = syncedAt
            existing.lastSyncError = nil
            existing.conflictRecipeData = nil
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
            existing.imagesData = try JSONEncoder().encode(recipe.images)
            existing.syncState = .pendingUpload
            existing.lastSyncError = nil
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

    func syncError(for id: String) throws -> String? {
        try modelContext.fetch(FetchDescriptor<StoredRecipe>())
            .first(where: { $0.id == id })?
            .lastSyncError
    }

    func conflictServerRecipe(for id: String) throws -> RecipeTransport? {
        guard let data = try modelContext.fetch(FetchDescriptor<StoredRecipe>())
            .first(where: { $0.id == id })?.conflictRecipeData else { return nil }
        return try JSONDecoder().decode(RecipeTransport.self, from: data)
    }

    func markSyncState(_ state: RecipeSyncState, for id: String, error: String? = nil) throws {
        guard let storedRecipe = try modelContext.fetch(FetchDescriptor<StoredRecipe>())
            .first(where: { $0.id == id }) else { return }
        storedRecipe.syncState = state
        storedRecipe.lastSyncError = error
        try modelContext.save()
    }

    func resolveConflict(id: String, resolution: RecipeConflictResolution) throws {
        guard let storedRecipe = try modelContext.fetch(FetchDescriptor<StoredRecipe>())
            .first(where: { $0.id == id }) else {
            throw RecipeStoreError.conflictNotFound
        }

        switch resolution {
        case .keepLocal:
            storedRecipe.syncState = .pendingUpload
            storedRecipe.conflictRecipeData = nil
            storedRecipe.lastSyncError = nil
        case .keepServer:
            guard let data = storedRecipe.conflictRecipeData,
                  let serverRecipe = try? JSONDecoder().decode(RecipeTransport.self, from: data) else {
                throw RecipeStoreError.conflictNotFound
            }
            try apply(serverRecipe, to: storedRecipe)
            storedRecipe.syncState = .synced
            storedRecipe.conflictRecipeData = nil
            storedRecipe.lastSyncError = nil
            storedRecipe.lastSyncedAt = Date()
        }

        try modelContext.save()
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

    private func apply(_ recipe: RecipeTransport, to storedRecipe: StoredRecipe) throws {
        storedRecipe.name = recipe.name
        storedRecipe.recipeDescription = recipe.description
        storedRecipe.styleRecommendation = recipe.styleRecommendation
        storedRecipe.cameraModelID = recipe.cameraModelID
        storedRecipe.lens = recipe.lens
        storedRecipe.categoriesData = try JSONEncoder().encode(recipe.categories)
        storedRecipe.tagsData = try JSONEncoder().encode(recipe.tags)
        storedRecipe.isPublished = recipe.isPublished
        storedRecipe.sourceRecipeID = recipe.provenance?.sourceRecipeID
        storedRecipe.sourceAuthorID = recipe.provenance?.sourceAuthorID
        storedRecipe.updatedAt = recipe.updatedAt
        storedRecipe.settingsData = try JSONEncoder().encode(recipe.settings)
        storedRecipe.imagesData = try JSONEncoder().encode(recipe.images)
    }
}
