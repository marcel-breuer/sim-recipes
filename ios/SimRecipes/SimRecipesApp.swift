import SwiftUI

@main
struct SimRecipesApp: App {
    @StateObject private var authService: AuthService
    @StateObject private var profileService: ProfileService
    private let apiClient: any APIClient
    private let localStore: LocalRecipeStore

    init() {
        let apiClient = URLSessionAPIClient(baseURL: AppConfiguration.apiBaseURL)
        let authService = AuthService(apiClient: apiClient)
        _authService = StateObject(wrappedValue: authService)
        _profileService = StateObject(wrappedValue: ProfileService(authService: authService))
        self.apiClient = apiClient
        self.localStore = try! LocalRecipeStore()
    }

    var body: some Scene {
        WindowGroup {
            RootView(
                authService: authService,
                profileService: profileService,
                apiClient: apiClient,
                localStore: localStore
            )
        }
    }
}
