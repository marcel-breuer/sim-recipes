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
    @AppStorage("simrecipes.onboarding.completed") private var onboardingCompleted = false
    @AppStorage("simrecipes.onboarding.camera-model") private var preferredCameraModelID = "fujifilm-x-s20"

    var body: some View {
        if onboardingCompleted {
            mainTabs
        } else {
            OnboardingView(
                preferredCameraModelID: $preferredCameraModelID,
                onboardingCompleted: $onboardingCompleted
            )
        }
    }

    private var mainTabs: some View {
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

            ProfileView(
                authService: authService,
                profileService: profileService,
                apiClient: apiClient
            )
                .tabItem {
                    Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage)
                }
                .tag(AppTab.profile)
        }
    }
}

enum OnboardingInterest: String, CaseIterable, Identifiable {
    case street
    case portrait
    case landscape
    case travel
    case everyday

    var id: String { rawValue }

    var title: String {
        rawValue.capitalized
    }
}

private struct OnboardingView: View {
    @Binding var preferredCameraModelID: String
    @Binding var onboardingCompleted: Bool
    @State private var selectedInterests: Set<OnboardingInterest> = []

    private let cameraOptions = [
        (id: "fujifilm-x-s20", title: "Fujifilm X-S20"),
        (id: "fujifilm-x-t5", title: "Fujifilm X-T5")
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Build a recipe library that fits your camera and the way you photograph.")
                        .font(.headline)
                    Text("You can change these choices later in Profile. The starter recipes remain available offline.")
                        .foregroundStyle(.secondary)
                }

                Section("Your camera") {
                    Picker("Camera model", selection: $preferredCameraModelID) {
                        ForEach(cameraOptions, id: \.id) { camera in
                            Text(camera.title).tag(camera.id)
                        }
                    }
                }

                Section("What do you photograph?") {
                    ForEach(OnboardingInterest.allCases) { interest in
                        Button {
                            toggle(interest)
                        } label: {
                            HStack {
                                Text(interest.title)
                                Spacer()
                                if selectedInterests.contains(interest) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section("Ready to explore") {
                    Label("Starter recipes are available from Explore after onboarding.", systemImage: "sparkles")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Welcome to SimRecipes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start exploring") {
                        onboardingCompleted = true
                    }
                    .disabled(preferredCameraModelID.isEmpty)
                }
            }
        }
    }

    private func toggle(_ interest: OnboardingInterest) {
        if selectedInterests.contains(interest) {
            selectedInterests.remove(interest)
        } else {
            selectedInterests.insert(interest)
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
