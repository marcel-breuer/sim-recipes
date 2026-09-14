import Combine
import Foundation

@MainActor
final class ProfileService: ObservableObject {
    @Published private(set) var profile: ProfileTransport?
    @Published private(set) var collections: [RecipeCollectionTransport] = []
    @Published private(set) var isLoading = false

    private let authService: AuthService
    private let localCollectionStore: LocalCollectionStore
    private let encoder = JSONEncoder()

    init(authService: AuthService, localCollectionStore: LocalCollectionStore = LocalCollectionStore()) {
        self.authService = authService
        self.localCollectionStore = localCollectionStore
    }

    func loadCurrentProfile() async throws {
        guard let apiClient = authService.authenticatedAPIClient() else {
            profile = nil
            return
        }

        isLoading = true
        defer { isLoading = false }
        let request = APIRequest(method: .get, path: "me/profile")
        let response = try await apiClient.send(
            request,
            responseType: APIResponse<ProfileTransport>.self
        )
        profile = response.data
    }

    func loadCollections() async throws {
        let cachedCollections = (try? localCollectionStore.collections()) ?? []
        collections = cachedCollections
        guard let apiClient = authService.authenticatedAPIClient() else { return }

        do {
            collections = try await synchronizeCollections(cached: cachedCollections, with: apiClient)
            try localCollectionStore.save(collections)
        } catch {
            collections = cachedCollections
            if cachedCollections.isEmpty { throw error }
        }
    }

    func createCollection(name: String, isPublic: Bool = false) async throws {
        guard let apiClient = authService.authenticatedAPIClient() else {
            saveLocalCollection(name: name, isPublic: isPublic)
            return
        }

        do {
            let payload = CollectionNamePayload(name: name, isPublic: isPublic)
            let response = try await apiClient.send(
                APIRequest(method: .post, path: "collections", body: try encoder.encode(payload)),
                responseType: APIResponse<RecipeCollectionTransport>.self
            )
            collections.append(response.data)
            collections.sort { $0.sortOrder < $1.sortOrder }
            try localCollectionStore.save(collections)
        } catch {
            saveLocalCollection(name: name, isPublic: isPublic)
            throw error
        }
    }

    func updateCollection(_ collection: RecipeCollectionTransport) async throws {
        guard let apiClient = authService.authenticatedAPIClient() else {
            replaceLocalCollection(
                collection,
                syncState: collection.id.hasPrefix("local-") ? .pendingCreate : .pendingMembership
            )
            return
        }

        do {
            let payload = CollectionNamePayload(name: collection.name, isPublic: collection.isPublic)
            let response = try await apiClient.send(
                APIRequest(method: .patch, path: "collections/\(collection.id)", body: try encoder.encode(payload)),
                responseType: APIResponse<RecipeCollectionTransport>.self
            )
            replaceLocalCollection(response.data)
            try localCollectionStore.save(collections)
        } catch {
            replaceLocalCollection(
                collection,
                syncState: collection.id.hasPrefix("local-") ? .pendingCreate : .pendingMembership
            )
            throw error
        }
    }

    func deleteCollection(_ collection: RecipeCollectionTransport) async throws {
        guard let apiClient = authService.authenticatedAPIClient() else {
            collections.removeAll { $0.id == collection.id }
            try? localCollectionStore.save(collections)
            return
        }

        do {
            _ = try await apiClient.send(
                APIRequest(method: .delete, path: "collections/\(collection.id)"),
                responseType: APIResponse<DeletedResponse>.self
            )
            collections.removeAll { $0.id == collection.id }
            try localCollectionStore.save(collections)
        } catch {
            throw error
        }
    }

    func reorderCollections(_ collections: [RecipeCollectionTransport]) async throws {
        self.collections = collections.enumerated().map { index, collection in
            var updated = collection
            updated.sortOrder = index
            return updated
        }
        try localCollectionStore.save(self.collections)

        guard let apiClient = authService.authenticatedAPIClient() else { return }
        let payload = CollectionReorderPayload(collectionIDs: self.collections.map(\.id))
        do {
            let response = try await apiClient.send(
                APIRequest(method: .patch, path: "collections/reorder", body: try encoder.encode(payload)),
                responseType: APIResponse<[RecipeCollectionTransport]>.self
            )
            self.collections = response.data
            try localCollectionStore.save(self.collections)
        } catch {
            throw error
        }
    }

    func addRecipe(_ recipe: CollectionRecipeTransport, to collectionID: String) async throws {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        if !collections[index].recipes.contains(where: { $0.id == recipe.id }) {
            collections[index].recipes.append(recipe)
            collections[index].syncState = .pendingMembership
            try localCollectionStore.save(collections)
        }

        guard let apiClient = authService.authenticatedAPIClient() else { return }
        do {
            let response = try await apiClient.send(
                APIRequest(method: .put, path: "collections/\(collectionID)/recipes/\(recipe.id)"),
                responseType: APIResponse<RecipeCollectionTransport>.self
            )
            replaceLocalCollection(response.data)
            try localCollectionStore.save(collections)
        } catch {
            throw error
        }
    }

    func removeRecipe(_ recipeID: String, from collectionID: String) async throws {
        guard let index = collections.firstIndex(where: { $0.id == collectionID }) else { return }
        collections[index].recipes.removeAll { $0.id == recipeID }
        collections[index].syncState = .pendingMembership
        try localCollectionStore.save(collections)

        guard let apiClient = authService.authenticatedAPIClient() else { return }
        let response = try await apiClient.send(
            APIRequest(method: .delete, path: "collections/\(collectionID)/recipes/\(recipeID)"),
            responseType: APIResponse<RecipeCollectionTransport>.self
        )
        replaceLocalCollection(response.data)
        try localCollectionStore.save(collections)
    }

    func updateCurrentProfile(
        username: String,
        cameraModelID: String?,
        biography: String?
    ) async throws {
        guard let apiClient = authService.authenticatedAPIClient() else {
            return
        }

        isLoading = true
        defer { isLoading = false }
        let payload = ProfileUpdatePayload(
            username: username,
            cameraModelID: cameraModelID,
            biography: biography,
            removeProfileImage: false
        )
        let request = APIRequest(
            method: .patch,
            path: "me/profile",
            body: try encoder.encode(payload)
        )
        let response = try await apiClient.send(
            request,
            responseType: APIResponse<ProfileTransport>.self
        )
        profile = response.data
    }

    private func saveLocalCollection(name: String, isPublic: Bool) {
        let collection = RecipeCollectionTransport(
            id: "local-\(UUID().uuidString.lowercased())",
            name: name,
            isPublic: isPublic,
            sortOrder: collections.count,
            syncState: .pendingCreate
        )
        collections.append(collection)
        try? localCollectionStore.save(collections)
    }

    private func synchronizeCollections(
        cached: [RecipeCollectionTransport],
        with apiClient: any APIClient
    ) async throws -> [RecipeCollectionTransport] {
        let remoteResponse = try await apiClient.send(
            APIRequest(method: .get, path: "collections"),
            responseType: APIResponse<[RecipeCollectionTransport]>.self
        )
        var remoteCollections = remoteResponse.data

        for localCollection in cached where localCollection.syncState == .pendingCreate {
            let payload = CollectionNamePayload(
                name: localCollection.name,
                isPublic: localCollection.isPublic
            )
            let createdResponse = try await apiClient.send(
                APIRequest(method: .post, path: "collections", body: try encoder.encode(payload)),
                responseType: APIResponse<RecipeCollectionTransport>.self
            )
            var created = createdResponse.data
            for recipe in localCollection.recipes {
                let recipeResponse = try await apiClient.send(
                    APIRequest(method: .put, path: "collections/\(created.id)/recipes/\(recipe.id)"),
                    responseType: APIResponse<RecipeCollectionTransport>.self
                )
                created = recipeResponse.data
            }
            remoteCollections.append(created)
        }

        for localCollection in cached where localCollection.syncState == .pendingMembership {
            guard let remoteCollection = remoteCollections.first(where: { $0.id == localCollection.id }) else {
                continue
            }
            let localRecipeIDs = Set(localCollection.recipes.map(\.id))
            let remoteRecipeIDs = Set(remoteCollection.recipes.map(\.id))
            for recipe in localCollection.recipes where !remoteRecipeIDs.contains(recipe.id) {
                _ = try await apiClient.send(
                    APIRequest(method: .put, path: "collections/\(localCollection.id)/recipes/\(recipe.id)"),
                    responseType: APIResponse<RecipeCollectionTransport>.self
                )
            }
            for recipe in remoteCollection.recipes where !localRecipeIDs.contains(recipe.id) {
                _ = try await apiClient.send(
                    APIRequest(method: .delete, path: "collections/\(localCollection.id)/recipes/\(recipe.id)"),
                    responseType: APIResponse<RecipeCollectionTransport>.self
                )
            }
        }

        let refreshedResponse = try await apiClient.send(
            APIRequest(method: .get, path: "collections"),
            responseType: APIResponse<[RecipeCollectionTransport]>.self
        )
        return refreshedResponse.data
    }

    private func replaceLocalCollection(
        _ collection: RecipeCollectionTransport,
        syncState: CollectionSyncState? = nil
    ) {
        var collection = collection
        collection.syncState = syncState ?? .synced
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            collections[index] = collection
        } else {
            collections.append(collection)
        }
        collections.sort { $0.sortOrder < $1.sortOrder }
    }
}
