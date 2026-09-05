import SwiftUI

@main
struct SimRecipesApp: App {
    @StateObject private var authService: AuthService

    init() {
        let apiClient = URLSessionAPIClient(baseURL: AppConfiguration.apiBaseURL)
        _authService = StateObject(wrappedValue: AuthService(apiClient: apiClient))
    }

    var body: some Scene {
        WindowGroup {
            RootView(authService: authService)
        }
    }
}
