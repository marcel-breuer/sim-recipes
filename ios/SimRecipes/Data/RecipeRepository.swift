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

struct RecipeEngagementTransport: Codable, Equatable, Sendable {
    let recorded: Bool?
    let liked: Bool?
    let viewsCount: Int?
    let likesCount: Int?

    enum CodingKeys: String, CodingKey {
        case recorded, liked
        case viewsCount = "views_count"
        case likesCount = "likes_count"
    }
}

@MainActor
final class RecipeRepository {
    private let apiClient: any APIClient
    private let localStore: LocalRecipeStore
    private let imageCache: ImageCache

    init(
        apiClient: any APIClient,
        localStore: LocalRecipeStore,
        imageCache: ImageCache = ImageCache()
    ) {
        self.apiClient = apiClient
        self.localStore = localStore
        self.imageCache = imageCache
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
        let cachedRecipe = await cacheImages(for: recipe)
        if try localStore.mergeRemote(cachedRecipe) == .conflict {
            throw RecipeSyncError.conflict(recipeID: recipe.id)
        }
        return cachedRecipe
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
            let cachedRecipe = await cacheImages(for: recipe)
            if try localStore.mergeRemote(cachedRecipe) == .conflict {
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

    func communityRecipes(
        feed: RecipeFeed,
        filter: CommunityRecipeFilter = CommunityRecipeFilter(),
        page: Int = 1,
        perPage: Int = 20
    ) async throws -> RecipePageTransport {
        var queryItems = [URLQueryItem(
            name: "feed",
            value: feed.rawValue
        ), URLQueryItem(name: "page", value: String(page)), URLQueryItem(
            name: "per_page",
            value: String(perPage)
        )]

        let search = filter.search.trimmingCharacters(in: .whitespacesAndNewlines)
        if !search.isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if let cameraModelID = filter.cameraModelID {
            queryItems.append(URLQueryItem(name: "camera_model_id", value: cameraModelID))
        }
        if let filmSimulation = filter.filmSimulation, !filmSimulation.isEmpty {
            queryItems.append(URLQueryItem(name: "film_simulation", value: filmSimulation))
        }
        queryItems.append(contentsOf: filter.categorySlugs.map {
            URLQueryItem(name: "categories[]", value: $0)
        })
        queryItems.append(contentsOf: filter.tags.map {
            URLQueryItem(name: "tags[]", value: $0)
        })

        return try await apiClient.send(
            APIRequest(method: .get, path: "recipes", queryItems: queryItems),
            responseType: RecipePageTransport.self
        )
    }

    func recipe(id: String) async throws -> RecipeTransport {
        if let cachedRecipe = try localStore.recipe(id: id) {
            return cachedRecipe
        }

        return try await refreshRecipe(id: id)
    }

    func create(_ draft: RecipeDraft, categoryIDs: [String]) async throws -> RecipeTransport {
        let request = try makeMultipartRequest(
            method: .post,
            path: "recipes",
            draft: draft,
            categoryIDs: categoryIDs
        )
        let response = try await apiClient.send(request, responseType: APIResponse<RecipeTransport>.self)
        let cachedRecipe = await cacheImages(for: response.data)
        try localStore.mergeRemote(cachedRecipe)
        return cachedRecipe
    }

    func update(_ draft: RecipeDraft, categoryIDs: [String]) async throws -> RecipeTransport {
        guard let id = draft.id else {
            return try await create(draft, categoryIDs: categoryIDs)
        }

        let request = try makeMultipartRequest(
            method: .post,
            path: "recipes/\(id)",
            draft: draft,
            categoryIDs: categoryIDs
        )
        let response = try await apiClient.send(request, responseType: APIResponse<RecipeTransport>.self)
        let cachedRecipe = await cacheImages(for: response.data)
        try localStore.mergeRemote(cachedRecipe)
        return cachedRecipe
    }

    func publish(id: String) async throws -> RecipeTransport {
        let request = APIRequest(method: .post, path: "recipes/\(id)/publish")
        let response = try await apiClient.send(request, responseType: APIResponse<RecipeTransport>.self)
        let cachedRecipe = await cacheImages(for: response.data)
        try localStore.mergeRemote(cachedRecipe)
        return cachedRecipe
    }

    func copy(id: String) async throws -> RecipeTransport {
        let request = APIRequest(method: .post, path: "recipes/\(id)/copy")
        let response = try await apiClient.send(request, responseType: APIResponse<RecipeTransport>.self)
        let cachedRecipe = await cacheImages(for: response.data)
        try localStore.mergeRemote(cachedRecipe)
        return cachedRecipe
    }

    func recordView(id: String) async throws -> RecipeEngagementTransport {
        let request = APIRequest(method: .post, path: "recipes/\(id)/view")
        let response = try await apiClient.send(
            request,
            responseType: APIResponse<RecipeEngagementTransport>.self
        )
        return response.data
    }

    func like(id: String) async throws -> RecipeEngagementTransport {
        let request = APIRequest(method: .post, path: "recipes/\(id)/like")
        let response = try await apiClient.send(
            request,
            responseType: APIResponse<RecipeEngagementTransport>.self
        )
        return response.data
    }

    func unlike(id: String) async throws -> RecipeEngagementTransport {
        let request = APIRequest(method: .delete, path: "recipes/\(id)/like")
        let response = try await apiClient.send(
            request,
            responseType: APIResponse<RecipeEngagementTransport>.self
        )
        return response.data
    }

    private func cacheImages(for recipe: RecipeTransport) async -> RecipeTransport {
        var images: [RecipeImageTransport] = []
        for image in recipe.images {
            var cachedImage = image
            if let cachedURL = await imageCache.cachedURL(recipeID: recipe.id, imageID: image.id) {
                cachedImage = RecipeImageTransport(
                    id: image.id,
                    url: image.url,
                    derivativeURLs: image.derivativeURLs,
                    processingStatus: image.processingStatus,
                    localURL: cachedURL
                )
            } else {
                do {
                    let data = try await apiClient.download(
                        APIRequest(method: .get, path: "recipe-images/\(image.id)")
                    )
                    let cachedURL = try await imageCache.store(data, recipeID: recipe.id, imageID: image.id)
                    cachedImage = RecipeImageTransport(
                        id: image.id,
                        url: image.url,
                        derivativeURLs: image.derivativeURLs,
                        processingStatus: image.processingStatus,
                        localURL: cachedURL
                    )
                } catch {
                    // Metadata remains usable when an image is unavailable.
                }
            }
            images.append(cachedImage)
        }

        return RecipeTransport(
            id: recipe.id,
            name: recipe.name,
            description: recipe.description,
            styleRecommendation: recipe.styleRecommendation,
            cameraModelID: recipe.cameraModelID,
            cameraModelName: recipe.cameraModelName,
            lens: recipe.lens,
            categories: recipe.categories,
            tags: recipe.tags,
            isPublished: recipe.isPublished,
            provenance: recipe.provenance,
            updatedAt: recipe.updatedAt,
            settings: recipe.settings,
            images: images,
            author: recipe.author,
            publishedAt: recipe.publishedAt,
            viewsCount: recipe.viewsCount,
            likesCount: recipe.likesCount,
            downloadsCount: recipe.downloadsCount,
            isLiked: recipe.isLiked
        )
    }

    private func makeMultipartRequest(
        method: HTTPMethod,
        path: String,
        draft: RecipeDraft,
        categoryIDs: [String]
    ) throws -> APIRequest {
        var form = MultipartFormDataBuilder()
        form.append(name: "name", value: draft.name)
        form.append(name: "description", value: draft.description)
        form.append(name: "recommendation", value: draft.recommendation)
        form.append(name: "lens", value: draft.lens)
        form.append(name: "camera_model_id", value: draft.cameraModelID)
        try form.appendJSON(name: "categories", value: categoryIDs)
        try form.appendJSON(name: "tags", value: draft.tags)
        try form.appendJSON(name: "settings", value: draft.settings.map { [
            "setting_key": JSONValue.string($0.key),
            "value": $0.value
        ] as [String: JSONValue] })

        for image in draft.images {
            form.appendFile(
                name: "images[]",
                filename: image.filename,
                mimeType: image.mimeType,
                data: image.data
            )
        }

        let result = form.finalized()
        return APIRequest(
            method: method,
            path: path,
            body: result.data,
            contentType: result.contentType
        )
    }
}
