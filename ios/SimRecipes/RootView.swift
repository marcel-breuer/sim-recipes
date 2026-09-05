import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case explore
    case library
    case profile

    var title: String {
        switch self {
        case .explore:
            "Explore"
        case .library:
            "Library"
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
        case .profile:
            "person.crop.circle"
        }
    }
}

struct RootView: View {
    @ObservedObject var authService: AuthService
    @State private var selectedTab: AppTab = .explore

    var body: some View {
        TabView(selection: $selectedTab) {
            ExploreView()
                .tabItem {
                    Label(AppTab.explore.title, systemImage: AppTab.explore.systemImage)
                }
                .tag(AppTab.explore)

            LibraryView()
                .tabItem {
                    Label(AppTab.library.title, systemImage: AppTab.library.systemImage)
                }
                .tag(AppTab.library)

            ProfileView(authService: authService)
                .tabItem {
                    Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage)
                }
                .tag(AppTab.profile)
        }
    }
}
