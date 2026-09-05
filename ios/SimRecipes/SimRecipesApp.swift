import SwiftUI

@main
struct SimRecipesApp: App {
    @StateObject private var authService: AuthService
    @StateObject private var profileService: ProfileService

    init() {
        let apiClient = URLSessionAPIClient(baseURL: AppConfiguration.apiBaseURL)
        let authService = AuthService(apiClient: apiClient)
        _authService = StateObject(wrappedValue: authService)
        _profileService = StateObject(wrappedValue: ProfileService(authService: authService))
    }

    var body: some Scene {
        WindowGroup {
            RootView(authService: authService, profileService: profileService)
        }
    }
}
