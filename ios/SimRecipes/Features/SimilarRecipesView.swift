import SwiftUI

@MainActor
final class SimilarRecipesViewModel: ObservableObject {
    @Published private(set) var recipes: [RecipeTransport] = []
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let recipeID: String
    private let repository: RecipeRepository

    init(recipeID: String, repository: RecipeRepository) {
        self.recipeID = recipeID
        self.repository = repository
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            recipes = try await repository.similarRecipes(id: recipeID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct SimilarRecipesView: View {
    @StateObject private var viewModel: SimilarRecipesViewModel

    init(recipeID: String, repository: RecipeRepository) {
        _viewModel = StateObject(wrappedValue: SimilarRecipesViewModel(
            recipeID: recipeID,
            repository: repository
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Similar recipes")
                .font(.headline)

            if viewModel.isLoading {
                ProgressView("Finding similar recipes…")
            } else if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "wifi.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Try again") {
                    Task { await viewModel.load() }
                }
                .font(.subheadline)
            } else if viewModel.recipes.isEmpty {
                Text("No similar public recipes found yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.recipes) { recipe in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(recipe.name)
                            .font(.subheadline.bold())
                        Text([recipe.cameraModelName ?? recipe.cameraModelID, recipe.tags.joined(separator: ", ")]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }
}
