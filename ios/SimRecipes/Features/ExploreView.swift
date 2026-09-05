import SwiftUI

struct ExploreView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Find your next look")
                            .font(.largeTitle.bold())

                        Text("Discover film-simulation recipes for your Fujifilm camera.")
                            .foregroundStyle(.secondary)
                    }

                    ContentUnavailableView(
                        "No recipes yet",
                        systemImage: "camera.aperture",
                        description: Text("Community recipes will appear here when the feed is connected.")
                    )
                    .frame(maxWidth: .infinity)
                }
                .padding()
            }
            .navigationTitle("Explore")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ExploreView()
}
