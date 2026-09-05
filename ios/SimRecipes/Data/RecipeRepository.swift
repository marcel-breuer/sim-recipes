import Foundation

enum RecipeSyncError: LocalizedError, Equatable {
    case conflict(recipeID: String)

    var errorDescription: String? {
        switch self {
        case let .conflict(recipeID):
            "Recipe \(recipeID) has local changes that conflict with the server."
        }
    }
}

struct RecipePageSyncResult: Equatable {
    let recipes: [RecipeTransport]
    let currentPage: Int
    let lastPage: Int
    let conflicts: [String]
}

@MainActor
final class RecipeRepository {
    private let apiClient: any APIClient
    private let localStore: LocalRecipeStore

    init(apiClient: any APIClient, localStore: LocalRecipeStore) {
        self.apiClient = apiClient
        self.localStore = localStore
    }

    func cachedRecipes() throws -> [RecipeTransport] {
        try localStore.recipes()
    }

    func cachedRecipe(id: String) throws -> RecipeTransport? {
        try localStore.recipe(id: id)
    }

    func refreshRecipe(id: String) async throws -> RecipeTransport {
        let request = APIRequest(method: .get, path: "recipes/\(id)")
        let recipe = try await apiClient.send(request, responseType: RecipeTransport.self)
        if try localStore.mergeRemote(recipe) == .conflict {
            throw RecipeSyncError.conflict(recipeID: recipe.id)
        }
        return recipe
    }

    func refreshRecipes(page: Int = 1) async throws -> RecipePageSyncResult {
        let request = APIRequest(
            method: .get,
            path: "recipes",
            queryItems: [
                URLQueryItem(name: "scope", value: "personal"),
                URLQueryItem(name: "page", value: String(page))
            ]
        )
        let response = try await apiClient.send(request, responseType: RecipePageTransport.self)
        var conflicts: [String] = []

        for recipe in response.data {
            if try localStore.mergeRemote(recipe) == .conflict {
                conflicts.append(recipe.id)
            }
        }

        return RecipePageSyncResult(
            recipes: response.data,
            currentPage: response.meta.currentPage,
            lastPage: response.meta.lastPage,
            conflicts: conflicts
        )
    }

    func recipe(id: String) async throws -> RecipeTransport {
        if let cachedRecipe = try localStore.recipe(id: id) {
            return cachedRecipe
        }

        return try await refreshRecipe(id: id)
    }
}
