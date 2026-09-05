import SwiftUI

struct RecipeDetailView: View {
    let recipe: RecipeTransport
    var copyAction: (() async throws -> RecipeTransport)?
    var viewAction: (() async throws -> RecipeEngagementTransport)?
    var likeAction: (() async throws -> RecipeEngagementTransport)?
    var unlikeAction: (() async throws -> RecipeEngagementTransport)?
    @State private var isCopying = false
    @State private var isLiking = false
    @State private var isLiked: Bool
    @State private var likesCount: Int
    @State private var message: String?

    init(
        recipe: RecipeTransport,
        copyAction: (() async throws -> RecipeTransport)? = nil,
        viewAction: (() async throws -> RecipeEngagementTransport)? = nil,
        likeAction: (() async throws -> RecipeEngagementTransport)? = nil,
        unlikeAction: (() async throws -> RecipeEngagementTransport)? = nil
    ) {
        self.recipe = recipe
        self.copyAction = copyAction
        self.viewAction = viewAction
        self.likeAction = likeAction
        self.unlikeAction = unlikeAction
        _isLiked = State(initialValue: recipe.isLiked ?? false)
        _likesCount = State(initialValue: recipe.likesCount)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let imageURL = recipe.images.first?.localURL ?? recipe.images.first?.url {
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
                    if let author = recipe.author {
                        Text("By \(author.name)")
                            .foregroundStyle(.secondary)
                    }
                    if let publishedAt = recipe.publishedAt {
                        Text(publishedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let recommendation = recipe.styleRecommendation {
                        Text(recommendation)
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    if let description = recipe.description, !description.isEmpty {
                        Text(description)
                    }
                }

                HStack(spacing: 20) {
                    Label("\(recipe.viewsCount) views", systemImage: "eye")
                    Label("\(likesCount) likes", systemImage: isLiked ? "heart.fill" : "heart")
                    Label("\(recipe.downloadsCount) saves", systemImage: "square.and.arrow.down")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                if likeAction != nil || unlikeAction != nil {
                    Button {
                        Task { await toggleLike() }
                    } label: {
                        Label(
                            isLiked ? "Unlike recipe" : "Like recipe",
                            systemImage: isLiked ? "heart.fill" : "heart"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLiking)
                }

                Group {
                    LabeledContent("Camera", value: recipe.cameraModelName ?? recipe.cameraModelID)
                    LabeledContent("Camera ID", value: recipe.cameraModelID)
                    if let lens = recipe.lens {
                        LabeledContent("Lens", value: lens)
                    }
                    LabeledContent(
                        "Compatibility",
                        value: "Targeted for \(recipe.cameraModelName ?? recipe.cameraModelID)"
                    )
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
        .toolbar {
            if let copyAction {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task {
                            isCopying = true
                            defer { isCopying = false }
                            do {
                                _ = try await copyAction()
                                message = "The recipe was added to your library."
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                    } label: {
                        if isCopying {
                            ProgressView()
                        } else {
                            Label("Save", systemImage: "square.and.arrow.down")
                        }
                    }
                    .disabled(isCopying)
                }
            }
        }
        .task {
            guard let viewAction else { return }
            _ = try? await viewAction()
        }
        .alert("Recipe", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func toggleLike() async {
        guard !isLiking else { return }
        isLiking = true
        defer { isLiking = false }
        do {
            let response: RecipeEngagementTransport
            if isLiked, let unlikeAction {
                response = try await unlikeAction()
            } else if let likeAction {
                response = try await likeAction()
            } else {
                return
            }
            isLiked = response.liked ?? !isLiked
            if let count = response.likesCount {
                likesCount = count
            }
        } catch {
            message = error.localizedDescription
        }
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
