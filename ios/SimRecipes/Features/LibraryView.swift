import SwiftUI

struct LibraryView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Your library is empty",
                systemImage: "books.vertical",
                description: Text("Recipes you create or save will be available offline here.")
            )
            .navigationTitle("Library")
        }
    }
}

#Preview {
    LibraryView()
}
