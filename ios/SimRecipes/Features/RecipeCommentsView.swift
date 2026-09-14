import SwiftUI

@MainActor
final class RecipeCommentsViewModel: ObservableObject {
    @Published private(set) var comments: [RecipeCommentTransport] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?
    @Published var draft = ""

    private let recipeID: String
    private let service: RecipeCommentsService

    init(recipeID: String, service: RecipeCommentsService) {
        self.recipeID = recipeID
        self.service = service
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            comments = try await service.comments(for: recipeID)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func submit() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }

        do {
            let comment = try await service.addComment(to: recipeID, body: body)
            comments.append(comment)
            draft = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ comment: RecipeCommentTransport) async {
        guard comment.canDelete else { return }
        do {
            try await service.deleteComment(id: comment.id)
            comments.removeAll { $0.id == comment.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RecipeCommentsView: View {
    let recipeID: String
    let service: RecipeCommentsService
    let moderationService: ModerationService?
    let blockUserAction: ((String) async throws -> Void)?
    @StateObject private var viewModel: RecipeCommentsViewModel
    @State private var message: String?
    @State private var pendingBlockAuthor: RecipeCommentAuthorTransport?

    init(
        recipeID: String,
        service: RecipeCommentsService,
        moderationService: ModerationService? = nil,
        blockUserAction: ((String) async throws -> Void)? = nil
    ) {
        self.recipeID = recipeID
        self.service = service
        self.moderationService = moderationService
        self.blockUserAction = blockUserAction
        _viewModel = StateObject(wrappedValue: RecipeCommentsViewModel(
            recipeID: recipeID,
            service: service
        ))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Comments")
                .font(.headline)

            if let errorMessage = viewModel.errorMessage, viewModel.comments.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.bubble")
                    .font(.caption)
                    .foregroundStyle(.red)
                Button("Try again") {
                    Task { await viewModel.load() }
                }
            } else if viewModel.comments.isEmpty, viewModel.isLoading {
                ProgressView("Loading comments…")
            } else if viewModel.comments.isEmpty {
                Text("No comments yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.comments) { comment in
                    commentRow(comment)
                }
            }

            if moderationService != nil || blockUserAction != nil {
                HStack(alignment: .bottom, spacing: 8) {
                    TextField("Add a respectful comment", text: $viewModel.draft, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                    Button {
                        Task { await viewModel.submit() }
                    } label: {
                        if viewModel.isSubmitting {
                            ProgressView()
                        } else {
                            Image(systemName: "paperplane.fill")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isSubmitting)
                    .accessibilityLabel("Post comment")
                }
            }
        }
        .task {
            await viewModel.load()
        }
        .alert("Comments", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
        .confirmationDialog(
            "Block \(pendingBlockAuthor?.name ?? "this creator")?",
            isPresented: Binding(
                get: { pendingBlockAuthor != nil },
                set: { if !$0 { pendingBlockAuthor = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Block creator", role: .destructive) {
                guard let author = pendingBlockAuthor, let blockUserAction else { return }
                pendingBlockAuthor = nil
                Task {
                    do {
                        try await blockUserAction(author.id)
                        message = "The creator was blocked. Refresh the recipe to remove their content."
                    } catch {
                        message = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func commentRow(_ comment: RecipeCommentTransport) -> some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                Text(comment.author?.name ?? "Community member")
                    .font(.subheadline.bold())
                Text(comment.body)
                    .font(.body)
                if let createdAt = comment.createdAt {
                    Text(createdAt, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            Menu {
                if comment.canDelete {
                    Button("Delete comment", role: .destructive) {
                        Task { await viewModel.delete(comment) }
                    }
                }
                if let moderationService {
                    Button("Report comment", role: .destructive) {
                        Task {
                            do {
                                try await moderationService.reportComment(id: comment.id)
                                message = "Thanks. The comment was reported for review."
                            } catch {
                                message = error.localizedDescription
                            }
                        }
                    }
                }
                if let author = comment.author, blockUserAction != nil {
                    Button("Block creator", role: .destructive) {
                        pendingBlockAuthor = author
                    }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Comment actions")
        }
        .padding(.vertical, 4)
    }
}
