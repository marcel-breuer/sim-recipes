import Foundation
import XCTest
@testable import SimRecipes

final class SimRecipesTests: XCTestCase {
    func testRootTabsExposeCoreProductSections() {
        XCTAssertEqual(
            AppTab.allCases,
            [.explore, .library, .profile]
        )
    }

    func testAPIRequestResolvesRelativeAPIPathAndQuery() throws {
        let request = APIRequest(
            method: .get,
            path: "recipes/recipe-1",
            queryItems: [URLQueryItem(name: "include", value: "settings")]
        )

        let url = try request.url(relativeTo: URL(string: "https://api.example.test/api/v1")!)

        XCTAssertEqual(
            url.absoluteString,
            "https://api.example.test/api/v1/recipes/recipe-1?include=settings"
        )
    }

    func testRecipeTransportCodableRoundTrip() throws {
        let recipe = RecipeTransport(
            id: "recipe-1",
            name: "Soft Chrome",
            description: "A muted everyday recipe.",
            styleRecommendation: "Everyday street photography",
            cameraModelID: "fujifilm-x-s20",
            lens: "23mm prime",
            categories: ["Street", "Everyday"],
            tags: ["muted", "daylight"],
            isPublished: true,
            provenance: RecipeProvenanceTransport(sourceRecipeID: nil, sourceAuthorID: nil),
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            settings: [RecipeSettingTransport(key: "film_simulation", value: "Classic Chrome")]
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        XCTAssertEqual(try decoder.decode(RecipeTransport.self, from: encoder.encode(recipe)), recipe)
    }

    func testRecipeTransportDecodesAPIResourceShapeAndStructuredSettings() throws {
        let data = #"{
            "id": "recipe-1",
            "name": "Structured Recipe",
            "recommendation": "Street",
            "camera_model": {"id": "camera-1"},
            "categories": [{"id": "category-1", "name": "Street", "slug": "street"}],
            "tags": [{"id": "tag-1", "name": "muted", "slug": "muted"}],
            "status": "private",
            "settings": [
                {"key": "highlight_tone", "value": -2},
                {"key": "grain_effect", "value": {"roughness": "WEAK", "size": "SMALL"}}
            ],
            "images": []
        }"#.data(using: .utf8)!

        let recipe = try JSONDecoder().decode(RecipeTransport.self, from: data)

        XCTAssertEqual(recipe.cameraModelID, "camera-1")
        XCTAssertEqual(recipe.categories, ["Street"])
        XCTAssertEqual(recipe.tags, ["muted"])
        XCTAssertEqual(recipe.settings[0].value, .number(-2))
        XCTAssertEqual(
            recipe.settings[1].value,
            .object(["roughness": .string("WEAK"), "size": .string("SMALL")])
        )
    }

    func testMultipartBuilderIncludesJSONFieldsAndImageParts() throws {
        var builder = MultipartFormDataBuilder(boundary: "test-boundary")
        builder.append(name: "name", value: "Soft Chrome")
        try builder.appendJSON(name: "tags", value: ["muted", "daylight"])
        builder.appendFile(name: "images[]", filename: "example.jpg", mimeType: "image/jpeg", data: Data([1, 2, 3]))

        let result = builder.finalized()
        let body = String(decoding: result.data, as: UTF8.self)

        XCTAssertEqual(result.contentType, "multipart/form-data; boundary=test-boundary")
        XCTAssertTrue(body.contains("name=\"name\""))
        XCTAssertTrue(body.contains("Soft Chrome"))
        XCTAssertTrue(body.contains("[\"muted\",\"daylight\"]"))
        XCTAssertTrue(body.contains("filename=\"example.jpg\""))
    }

    @MainActor
    func testRecipeDraftStorePersistsImageBackedDrafts() throws {
        let suiteName = "SimRecipesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }

        let store = RecipeDraftStore(defaults: defaults)
        var draft = RecipeDraft()
        draft.name = "Offline draft"
        draft.images = [RecipeDraftImage(filename: "example.jpg", data: Data([1, 2, 3]))]

        try store.save(draft)

        XCTAssertEqual(try store.draft(id: "new"), draft)
    }

    func testProfileTransportCodableRoundTrip() throws {
        let profile = ProfileTransport(
            id: "profile-1",
            username: "marcel",
            displayName: "Marcel",
            biography: "Street photography recipes.",
            cameraModel: CameraModelTransport(id: "camera-1", name: "X-S20", slug: "x-s20"),
            profileImageURL: URL(string: "https://cdn.example.test/profile.jpg"),
            publishedRecipes: [
                PublishedRecipeSummaryTransport(
                    id: "recipe-1",
                    name: "Soft Chrome",
                    description: nil,
                    cameraModel: nil,
                    publishedAt: Date(timeIntervalSince1970: 1_700_000_000)
                )
            ]
        )

        XCTAssertEqual(try JSONDecoder().decode(ProfileTransport.self, from: JSONEncoder().encode(profile)), profile)
    }

    func testAPIErrorPayloadPreservesValidationMessages() throws {
        let payload = APIErrorPayload(
            message: "The given data was invalid.",
            errors: ["name": ["The name field is required."]]
        )

        XCTAssertEqual(
            try JSONDecoder().decode(APIErrorPayload.self, from: JSONEncoder().encode(payload)),
            payload
        )
    }

    @MainActor
    func testAuthServiceRestoresAndLogsOutKeychainBackedSession() async throws {
        let session = AuthSession(
            token: "token-1",
            expiresAt: Date().addingTimeInterval(3600),
            user: AuthenticatedUser(id: "user-1", name: "Marcel", email: "marcel@example.test")
        )
        let credentialStore = MemoryCredentialStore()
        credentialStore.data = try JSONEncoder().encode(session)
        let apiClient = StubAPIClient(
            responses: [APIResponse(data: LogoutResponse(loggedOut: true))]
        )
        let authService = AuthService(apiClient: apiClient, credentialStore: credentialStore)

        XCTAssertEqual(authService.session, session)

        try await authService.logout()

        XCTAssertNil(authService.session)
        XCTAssertNil(credentialStore.data)
        XCTAssertEqual(apiClient.requests, ["auth/logout"])
    }

    @MainActor
    func testRepositoryUsesLocalRecipeWithoutCallingAPI() async throws {
        let recipe = makeRecipe(id: "cached")
        let apiClient = StubAPIClient()
        let localStore = try LocalRecipeStore(inMemory: true)
        try localStore.upsert(recipe)
        let repository = RecipeRepository(apiClient: apiClient, localStore: localStore)

        let result = try await repository.recipe(id: recipe.id)

        XCTAssertEqual(result, recipe)
        XCTAssertTrue(apiClient.requests.isEmpty)
    }

    @MainActor
    func testRepositoryRefreshesRemoteRecipeAndPersistsIt() async throws {
        let recipe = makeRecipe(id: "remote")
        let apiClient = StubAPIClient(responses: [recipe])
        let localStore = try LocalRecipeStore(inMemory: true)
        let repository = RecipeRepository(apiClient: apiClient, localStore: localStore)

        let result = try await repository.recipe(id: recipe.id)

        XCTAssertEqual(result, recipe)
        XCTAssertEqual(try localStore.recipe(id: recipe.id), recipe)
        XCTAssertEqual(apiClient.requests, ["recipes/remote"])
        XCTAssertEqual(try localStore.syncState(for: recipe.id), .synced)
    }

    @MainActor
    func testRepositoryReportsConflictForPendingPrivateRecipe() async throws {
        let localRecipe = makeRecipe(id: "conflict", isPublished: false)
        let remoteRecipe = makeRecipe(id: "conflict", name: "Remote update", isPublished: false)
        let apiClient = StubAPIClient(responses: [remoteRecipe])
        let localStore = try LocalRecipeStore(inMemory: true)
        try localStore.saveLocally(localRecipe)
        let repository = RecipeRepository(apiClient: apiClient, localStore: localStore)

        do {
            _ = try await repository.refreshRecipe(id: localRecipe.id)
            XCTFail("Expected a sync conflict")
        } catch let error as RecipeSyncError {
            XCTAssertEqual(error, .conflict(recipeID: localRecipe.id))
        }

        XCTAssertEqual(try localStore.syncState(for: localRecipe.id), .conflict)
    }

    @MainActor
    func testRepositorySynchronizesPaginatedRecipes() async throws {
        let firstRecipe = makeRecipe(id: "page-1")
        let secondRecipe = makeRecipe(id: "page-2")
        let page = RecipePageTransport(
            data: [firstRecipe, secondRecipe],
            meta: RecipePageMetadata(currentPage: 2, lastPage: 3, perPage: 2, total: 6),
            links: RecipePageLinks(next: URL(string: "https://api.example.test/api/v1/recipes?page=3"))
        )
        let apiClient = StubAPIClient(responses: [page])
        let localStore = try LocalRecipeStore(inMemory: true)
        let repository = RecipeRepository(apiClient: apiClient, localStore: localStore)

        let result = try await repository.refreshRecipes(page: 2)

        XCTAssertEqual(result.recipes, [firstRecipe, secondRecipe])
        XCTAssertEqual(result.currentPage, 2)
        XCTAssertEqual(result.lastPage, 3)
        XCTAssertTrue(result.conflicts.isEmpty)
        XCTAssertEqual(
            try localStore.recipes().map(\.id).sorted(),
            [firstRecipe.id, secondRecipe.id].sorted()
        )
        XCTAssertEqual(apiClient.requests, ["recipes"])
    }

    @MainActor
    func testPublishedRecipesCannotBeEditedLocally() throws {
        let localStore = try LocalRecipeStore(inMemory: true)
        try localStore.upsert(makeRecipe(id: "published"))

        XCTAssertThrowsError(try localStore.saveLocally(makeRecipe(id: "published", name: "Changed"))) { error in
            XCTAssertEqual(error as? RecipeStoreError, .publishedRecipeIsImmutable)
        }
    }

    private func makeRecipe(
        id: String,
        name: String = "Soft Chrome",
        isPublished: Bool = true
    ) -> RecipeTransport {
        RecipeTransport(
            id: id,
            name: name,
            description: "A muted everyday recipe.",
            styleRecommendation: nil,
            cameraModelID: "fujifilm-x-s20",
            lens: nil,
            categories: ["Everyday"],
            tags: ["muted"],
            isPublished: isPublished,
            provenance: nil,
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            settings: [RecipeSettingTransport(key: "film_simulation", value: "Classic Chrome")]
        )
    }

    func testOnlyUSBPTPCameraWithX20ModelNameIsCandidate() {
        let camera = CameraDescriptor(
            id: "camera-1",
            name: "FUJIFILM X-S20",
            productKind: "Camera",
            serialNumber: "serial-1",
            transportType: "USB",
            usbVendorID: 1,
            usbProductID: 2,
            supportsPTP: true
        )

        XCTAssertTrue(camera.isX20Candidate)
    }

    func testNameAloneDoesNotQualifyCameraCandidate() {
        let camera = CameraDescriptor(
            id: "camera-1",
            name: "X-S20",
            productKind: "Camera",
            serialNumber: nil,
            transportType: "USB",
            usbVendorID: 0,
            usbProductID: 0,
            supportsPTP: true
        )

        XCTAssertFalse(camera.isX20Candidate)
    }

    func testGetDeviceInfoCommandIsReadOnlyPTPCommand() {
        XCTAssertEqual(
            Array(PTPCommand.getDeviceInfo(transactionID: 1).encoded),
            [12, 0, 0, 0, 1, 0, 1, 16, 1, 0, 0, 0]
        )
    }

    func testGetDevicePropertyValueCommandUsesPropertyParameter() {
        XCTAssertEqual(
            Array(PTPCommand.getDevicePropValue(propertyCode: 0xD18C, transactionID: 1).encoded),
            [16, 0, 0, 0, 1, 0, 21, 16, 1, 0, 0, 0, 140, 209, 0, 0]
        )
    }

    func testSetDevicePropertyValueCommandAndDataContainerEncodeSeparately() {
        let command = PTPCommand.setDevicePropValue(propertyCode: 0xD192, transactionID: 7)
        let data = PTPDataContainer(code: command.code, transactionID: 7, payload: Data([2, 0])).encoded

        XCTAssertEqual(
            Array(command.encoded),
            [16, 0, 0, 0, 1, 0, 22, 16, 7, 0, 0, 0, 146, 209, 0, 0]
        )
        XCTAssertEqual(
            Array(data),
            [14, 0, 0, 0, 2, 0, 22, 16, 7, 0, 0, 0, 2, 0]
        )
    }

    func testWriteValidatorRequiresMatchingConfirmationAndSupportedProperties() {
        let properties = [UInt16(0xD192): Data([1, 0])]
        let supportedProperties: Set<UInt16> = [0xD192]

        XCTAssertEqual(
            CameraSlotWriteValidator.validationError(
                slot: .c1,
                properties: properties,
                supportedPropertyCodes: supportedProperties,
                confirmation: CameraSlotOverwriteConfirmation(slot: .c2)
            )?.errorDescription,
            CameraServiceError.confirmationDoesNotMatchSlot.errorDescription
        )

        XCTAssertNil(
            CameraSlotWriteValidator.validationError(
                slot: .c1,
                properties: properties,
                supportedPropertyCodes: supportedProperties,
                confirmation: CameraSlotOverwriteConfirmation(slot: .c1)
            )
        )

        XCTAssertEqual(
            CameraSlotWriteValidator.validationError(
                slot: .c1,
                properties: properties,
                supportedPropertyCodes: [],
                confirmation: CameraSlotOverwriteConfirmation(slot: .c1)
            )?.errorDescription,
            CameraServiceError.unsupportedProperty(0xD192).errorDescription
        )
    }

    func testPTPResponseHeaderRejectsMalformedResponses() {
        XCTAssertNil(PTPResponseHeader(data: Data(repeating: 0, count: 11)))
        XCTAssertNil(PTPResponseHeader(data: Data(repeating: 0, count: 12)))
    }

    func testPTPResponseHeaderParsesSuccessfulResponse() {
        let response = Data([12, 0, 0, 0, 3, 0, 1, 32, 1, 0, 0, 0])

        XCTAssertEqual(
            PTPResponseHeader(data: response),
            PTPResponseHeader(
                length: 12,
                type: 3,
                responseCode: PTPResponseHeader.successResponseCode,
                transactionID: 1
            )
        )
    }
}
