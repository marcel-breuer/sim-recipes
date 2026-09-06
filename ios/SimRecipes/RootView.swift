import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case explore
    case library
    case create
    case profile

    var title: String {
        switch self {
        case .explore:
            "Explore"
        case .library:
            "Library"
        case .create:
            "Create"
        case .profile:
            "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .explore:
            "sparkles"
        case .library:
            "books.vertical"
        case .create:
            "plus.circle"
        case .profile:
            "person.crop.circle"
        }
    }
}

struct RootView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var profileService: ProfileService
    let apiClient: any APIClient
    let localStore: LocalRecipeStore
    let cameraService: any CameraService
    @State private var selectedTab: AppTab = .explore

    var body: some View {
        TabView(selection: $selectedTab) {
            ExploreView(
                authService: authService,
                apiClient: apiClient,
                localStore: localStore,
                cameraService: cameraService
            )
                .tabItem {
                    Label(AppTab.explore.title, systemImage: AppTab.explore.systemImage)
                }
                .tag(AppTab.explore)

            LibraryView(
                authService: authService,
                apiClient: apiClient,
                localStore: localStore,
                cameraService: cameraService
            )
                .tabItem {
                    Label(AppTab.library.title, systemImage: AppTab.library.systemImage)
                }
                .tag(AppTab.library)

            CreateRecipeView(
                authService: authService,
                apiClient: apiClient,
                localStore: localStore
            )
                .tabItem {
                    Label(AppTab.create.title, systemImage: AppTab.create.systemImage)
                }
                .tag(AppTab.create)

            ProfileView(authService: authService, profileService: profileService)
                .tabItem {
                    Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage)
                }
                .tag(AppTab.profile)
        }
    }
}

private struct CreateRecipeView: View {
    @ObservedObject var authService: AuthService
    let apiClient: any APIClient
    let localStore: LocalRecipeStore

    var body: some View {
        NavigationStack {
            Group {
                if authService.session == nil {
                    ContentUnavailableView(
                        "Sign in to create recipes",
                        systemImage: "plus.circle",
                        description: Text("Create recipes and save them to your library after signing in.")
                    )
                } else {
                    editor
                }
            }
            .navigationTitle("Create")
        }
    }

    @ViewBuilder
    private var editor: some View {
        if let session = authService.session {
            let authenticatedClient = BearerAPIClient(apiClient: apiClient, accessToken: session.token)
            let repository = RecipeRepository(apiClient: authenticatedClient, localStore: localStore)
            let capabilityService = CameraCapabilityService(apiClient: authenticatedClient)
            RecipeEditorView(
                viewModel: RecipeEditorViewModel(
                    draft: RecipeDraft(),
                    repository: repository,
                    capabilityService: capabilityService
                )
            )
        }
    }
}
