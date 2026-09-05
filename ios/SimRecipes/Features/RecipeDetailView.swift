import SwiftUI

struct RecipeDetailView: View {
    let recipe: RecipeTransport

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let imageURL = recipe.images.first?.url {
                    AsyncImage(url: imageURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Rectangle().fill(.quaternary)
                    }
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(recipe.name)
                        .font(.largeTitle.bold())
                    if let recommendation = recipe.styleRecommendation {
                        Text(recommendation)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    if let description = recipe.description, !description.isEmpty {
                        Text(description)
                    }
                }

                LabeledContent("Camera", value: recipe.cameraModelID)
                if let lens = recipe.lens {
                    LabeledContent("Lens", value: lens)
                }
                if !recipe.categories.isEmpty {
                    LabeledContent("Categories", value: recipe.categories.joined(separator: ", "))
                }
                if !recipe.tags.isEmpty {
                    LabeledContent("Tags", value: recipe.tags.map { "#\($0)" }.joined(separator: " "))
                }

                if !recipe.settings.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Settings")
                            .font(.headline)
                        ForEach(recipe.settings, id: \.key) { setting in
                            LabeledContent(setting.key, value: setting.value.displayValue)
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Recipe")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private extension JSONValue {
    var displayValue: String {
        switch self {
        case let .string(value):
            value
        case let .number(value):
            String(value)
        case let .boolean(value):
            value ? "On" : "Off"
        case let .object(value):
            value.keys.sorted().map { "\($0): \(value[$0]?.displayValue ?? "—")" }.joined(separator: ", ")
        case let .array(value):
            value.map(\.displayValue).joined(separator: ", ")
        case .null:
            "—"
        }
    }
}
