import SwiftUI

struct ProfileView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Sign in to create a profile",
                systemImage: "person.crop.circle",
                description: Text("Your profile and published recipes will appear here.")
            )
            .navigationTitle("Profile")
        }
    }
}

#Preview {
    ProfileView()
}
