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

struct RecipeComparisonView: View {
    @Environment(\.dismiss) private var dismiss
    let recipes: [RecipeTransport]
    let contextFilter: RecipeExampleContextFilter

    private var sharedContextFilter: RecipeExampleContextFilter {
        guard recipes.count == 2 else { return RecipeExampleContextFilter() }
        let left = recipes[0].images.compactMap(\.exampleContext)
        let right = recipes[1].images.compactMap(\.exampleContext)
        var best = RecipeExampleContextFilter()
        for leftContext in left {
            for rightContext in right {
                let candidate = RecipeExampleContextFilter(
                    subjects: sharedValues(leftContext.subjects, rightContext.subjects),
                    lighting: sharedValues(leftContext.lighting, rightContext.lighting),
                    looks: sharedValues(leftContext.looks, rightContext.looks)
                )
                if contextScore(candidate) > contextScore(best) {
                    best = candidate
                }
            }
        }
        return best
    }

    private var effectiveContextFilter: RecipeExampleContextFilter? {
        if !contextFilter.isEmpty { return contextFilter }
        return sharedContextFilter.isEmpty ? nil : sharedContextFilter
    }

    private var settingKeys: [String] {
        Set(recipes.flatMap { $0.settings.map(\.key) }).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                contextExplanation

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 12) {
                        ForEach(recipes) { recipe in
                            exampleColumn(for: recipe)
                                .frame(width: 280, alignment: .topLeading)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Recipe settings")
                        .font(.headline)
                    Text("Differences are marked for quick review.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(settingKeys, id: \.self) { key in
                        let values = recipes.map { value(for: key, in: $0) }
                        let differs = Set(values).count > 1
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(key.replacingOccurrences(of: "_", with: " ").capitalized)
                                    .font(.subheadline.weight(.semibold))
                                if differs {
                                    Label("Different", systemImage: "arrow.left.arrow.right")
                                        .font(.caption2)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(width: 112, alignment: .leading)

                            ForEach(recipes.indices, id: \.self) { index in
                                Text(values[index])
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.vertical, 7)
                        .background(differs ? Color.accentColor.opacity(0.08) : Color.clear)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Compare recipes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
    }

    @ViewBuilder
    private var contextExplanation: some View {
        if !contextFilter.isEmpty {
            Text("Example photos match these selected labels: \(contextLabels(contextFilter).joined(separator: " · ")).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else if !sharedContextFilter.isEmpty {
            Text("Example photos are matched using the labels shared by both recipes: \(contextLabels(sharedContextFilter).joined(separator: " · ")).")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Label("These recipes have no shared context labels. Photos below are real examples, but similar shooting conditions are not confirmed.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func exampleColumn(for recipe: RecipeTransport) -> some View {
        let images = recipe.images.filter { image in
            guard let effectiveContextFilter else { return true }
            return effectiveContextFilter.matches(image.exampleContext)
        }

        return VStack(alignment: .leading, spacing: 8) {
            Text(recipe.name)
                .font(.headline)
                .lineLimit(2)
            Text(recipe.cameraModelName ?? recipe.cameraModelID)
                .font(.caption)
                .foregroundStyle(.secondary)

            if images.isEmpty {
                ContentUnavailableView(
                    "No matching example photo",
                    systemImage: "photo",
                    description: Text("This recipe has no image labeled with the selected context.")
                )
                .frame(height: 220)
            } else {
                ForEach(images) { image in
                    VStack(alignment: .leading, spacing: 5) {
                        if let imageURL = image.localURL ?? image.url {
                            AsyncImage(url: imageURL) { loadedImage in
                                loadedImage.resizable().scaledToFill()
                            } placeholder: {
                                Rectangle().fill(.quaternary)
                            }
                            .frame(height: 210)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        if let context = image.exampleContext, context.hasLabels {
                            Text(context.displayLabels.joined(separator: " · "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Context not labeled")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
    }

    private func value(for key: String, in recipe: RecipeTransport) -> String {
        recipe.settings.first(where: { $0.key == key })?.value.displayValue ?? "Not set"
    }

    private func sharedValues(_ left: [String], _ right: [String]) -> [String] {
        Set(left).intersection(Set(right)).sorted()
    }

    private func contextScore(_ filter: RecipeExampleContextFilter) -> Int {
        filter.subjects.count + filter.lighting.count + filter.looks.count
    }

    private func contextLabels(_ filter: RecipeExampleContextFilter) -> [String] {
        filter.subjects.map { RecipeExampleContextOptions.title(for: $0, in: RecipeExampleContextOptions.subjects) }
            + filter.lighting.map { RecipeExampleContextOptions.title(for: $0, in: RecipeExampleContextOptions.lighting) }
            + filter.looks.map { RecipeExampleContextOptions.title(for: $0, in: RecipeExampleContextOptions.looks) }
    }
}
