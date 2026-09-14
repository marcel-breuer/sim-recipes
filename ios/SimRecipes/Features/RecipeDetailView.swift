import SwiftUI

struct RecipeDetailView: View {
    let recipe: RecipeTransport
    var transferService: (any CameraService)?
    var collections: [RecipeCollectionTransport] = []
    var addToCollectionAction: ((String) async throws -> Void)?
    var copyAction: (() async throws -> RecipeTransport)?
    var viewAction: (() async throws -> RecipeEngagementTransport)?
    var likeAction: (() async throws -> RecipeEngagementTransport)?
    var unlikeAction: (() async throws -> RecipeEngagementTransport)?
    var followAction: (() async throws -> FollowResponse)?
    var unfollowAction: (() async throws -> FollowResponse)?
    var reportAction: (() async throws -> Void)?
    var blockAction: (() async throws -> Void)?
    @State private var isCopying = false
    @State private var isLiking = false
    @State private var isLiked: Bool
    @State private var likesCount: Int
    @State private var isFollowingAuthor: Bool
    @State private var message: String?
    @State private var isSubmittingSafetyAction = false

    init(
        recipe: RecipeTransport,
        transferService: (any CameraService)? = nil,
        collections: [RecipeCollectionTransport] = [],
        addToCollectionAction: ((String) async throws -> Void)? = nil,
        copyAction: (() async throws -> RecipeTransport)? = nil,
        viewAction: (() async throws -> RecipeEngagementTransport)? = nil,
        likeAction: (() async throws -> RecipeEngagementTransport)? = nil,
        unlikeAction: (() async throws -> RecipeEngagementTransport)? = nil,
        followAction: (() async throws -> FollowResponse)? = nil,
        unfollowAction: (() async throws -> FollowResponse)? = nil,
        reportAction: (() async throws -> Void)? = nil,
        blockAction: (() async throws -> Void)? = nil
    ) {
        self.recipe = recipe
        self.transferService = transferService
        self.collections = collections
        self.addToCollectionAction = addToCollectionAction
        self.copyAction = copyAction
        self.viewAction = viewAction
        self.likeAction = likeAction
        self.unlikeAction = unlikeAction
        self.followAction = followAction
        self.unfollowAction = unfollowAction
        self.reportAction = reportAction
        self.blockAction = blockAction
        _isLiked = State(initialValue: recipe.isLiked ?? false)
        _likesCount = State(initialValue: recipe.likesCount)
        _isFollowingAuthor = State(initialValue: false)
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
                        HStack {
                            Text("By \(author.name)")
                                .foregroundStyle(.secondary)
                            if followAction != nil || unfollowAction != nil {
                                Button(isFollowingAuthor ? "Following" : "Follow") {
                                    Task { await toggleFollow() }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(isLiking)
                            }
                        }
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
            if let transferService {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        CameraTransferView(recipe: recipe, cameraService: transferService)
                    } label: {
                        Label("Transfer to Camera", systemImage: "arrow.down.to.line.compact")
                    }
                    .accessibilityLabel("Transfer recipe to camera")
                }
            }
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
            if let addToCollectionAction, !collections.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        ForEach(collections) { collection in
                            Button(collection.name) {
                                Task {
                                    do {
                                        try await addToCollectionAction(collection.id)
                                        message = "Added to \(collection.name)."
                                    } catch {
                                        message = error.localizedDescription
                                    }
                                }
                            }
                        }
                    } label: {
                        Label("Add to collection", systemImage: "folder.badge.plus")
                    }
                }
            }
            if reportAction != nil || blockAction != nil {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let reportAction {
                            Button("Report recipe", role: .destructive) {
                                Task { await submitSafetyAction(reportAction, success: "Thanks. The recipe was reported for review.") }
                            }
                        }
                        if let blockAction {
                            Button("Block creator", role: .destructive) {
                                Task { await submitSafetyAction(blockAction, success: "The creator was blocked.") }
                            }
                        }
                    } label: {
                        Label("Safety options", systemImage: "ellipsis.circle")
                    }
                    .disabled(isSubmittingSafetyAction)
                    .accessibilityLabel("Safety options")
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

    private func toggleFollow() async {
        do {
            let response: FollowResponse
            if isFollowingAuthor, let unfollowAction {
                response = try await unfollowAction()
            } else if let followAction {
                response = try await followAction()
            } else {
                return
            }
            isFollowingAuthor = response.following
        } catch {
            message = error.localizedDescription
        }
    }

    private func submitSafetyAction(
        _ action: @escaping () async throws -> Void,
        success: String
    ) async {
        guard !isSubmittingSafetyAction else { return }
        isSubmittingSafetyAction = true
        defer { isSubmittingSafetyAction = false }

        do {
            try await action()
            message = success
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
