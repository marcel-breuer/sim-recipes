import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var profileService: ProfileService
    @State private var errorMessage: String?
    @State private var username = ""
    @State private var biography = ""
    @State private var newCollectionName = ""
    @State private var hasLoadedProfile = false

    var body: some View {
        NavigationStack {
            Group {
                if authService.session == nil {
                    signInView
                } else {
                    signedInView
                }
            }
            .navigationTitle("Profile")
            .alert("Authentication Error", isPresented: errorIsPresented) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "Please try again.")
            }
            .task(id: authService.session?.token) {
                await loadProfile()
            }
        }
    }

    private var signInView: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Sign in to create a profile",
                systemImage: "person.crop.circle",
                description: Text("Your profile and published recipes will appear here.")
            )

            SignInWithAppleButton(.signIn) { request in
                request.requestedScopes = [.fullName, .email]
            } onCompletion: { result in
                guard case let .success(authorization) = result,
                      let credential = authorization.credential as? ASAuthorizationAppleIDCredential
                else {
                    if case let .failure(error) = result {
                        errorMessage = error.localizedDescription
                    }
                    return
                }

                Task { @MainActor in
                    do {
                        try await authService.signIn(with: credential)
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
            .signInWithAppleButtonStyle(.black)
            .frame(height: 48)
            .padding(.horizontal)
        }
    }

    private var signedInView: some View {
        Form {
            Section("Profile") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                TextEditor(text: $biography)
                    .frame(minHeight: 100)
            }

            if let profile = profileService.profile {
                Section("Community") {
                    HStack {
                        Label("\(profile.followersCount) followers", systemImage: "person.2")
                        Spacer()
                        Label("\(profile.followingCount) following", systemImage: "person.badge.plus")
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }

                Section("Published recipes") {
                    if profile.publishedRecipes.isEmpty {
                        Text("No published recipes yet.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(profile.publishedRecipes) { recipe in
                            VStack(alignment: .leading) {
                                Text(recipe.name)
                                    .font(.headline)
                                if let description = recipe.description {
                                    Text(description)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }

            Section("Collections") {
                EditButton()
                HStack {
                    TextField("New collection", text: $newCollectionName)
                    Button {
                        let name = newCollectionName.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !name.isEmpty else { return }
                        Task {
                            do {
                                try await profileService.createCollection(name: name)
                                newCollectionName = ""
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        }
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .accessibilityLabel("Create collection")
                }

                if profileService.collections.isEmpty {
                    Text("Create collections to organize recipes for offline use.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(profileService.collections) { collection in
                        ProfileCollectionRow(
                            collection: collection,
                            save: { updated in
                                try await profileService.updateCollection(updated)
                            },
                            delete: {
                                try await profileService.deleteCollection(collection)
                            }
                        )
                    }
                    .onMove { offsets, newOffset in
                        var reordered = profileService.collections
                        reordered.move(fromOffsets: offsets, toOffset: newOffset)
                        Task {
                            try? await profileService.reorderCollections(reordered)
                        }
                    }
                }
            }

            Section {
                Button("Save Profile") {
                    Task { @MainActor in
                        do {
                            try await profileService.updateCurrentProfile(
                                username: username,
                                cameraModelID: profileService.profile?.cameraModel?.id,
                                biography: biography.isEmpty ? nil : biography
                            )
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .disabled(username.isEmpty || profileService.isLoading)

                Button("Sign Out", role: .destructive) {
                    Task { @MainActor in
                        do {
                            try await authService.logout()
                            hasLoadedProfile = false
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
            }

            Section("Safety and support") {
                Link("Community standards", destination: AppConfiguration.communityStandardsURL)
                Link("Contact support", destination: AppConfiguration.supportEmailURL)
            }
        }
    }

    private func loadProfile() async {
        guard authService.session != nil, !hasLoadedProfile else {
            return
        }

        do {
            try await profileService.loadCurrentProfile()
            try await profileService.loadCollections()
            username = profileService.profile?.username ?? ""
            biography = profileService.profile?.biography ?? ""
            hasLoadedProfile = true
        } catch let APIClientError.server(statusCode, _) where statusCode == 404 {
            try? await profileService.loadCollections()
            hasLoadedProfile = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}

private struct ProfileCollectionRow: View {
    let collection: RecipeCollectionTransport
    let save: (RecipeCollectionTransport) async throws -> Void
    let delete: () async throws -> Void
    @State private var name: String
    @State private var isPublic: Bool
    @State private var isSaving = false

    init(
        collection: RecipeCollectionTransport,
        save: @escaping (RecipeCollectionTransport) async throws -> Void,
        delete: @escaping () async throws -> Void
    ) {
        self.collection = collection
        self.save = save
        self.delete = delete
        _name = State(initialValue: collection.name)
        _isPublic = State(initialValue: collection.isPublic)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Collection name", text: $name)
                .textInputAutocapitalization(.words)
            HStack {
                Toggle("Public", isOn: $isPublic)
                Spacer()
                Button("Save") {
                    Task { await saveChanges() }
                }
                .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("\(collection.recipes.count) recipes")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .swipeActions {
            Button("Delete", role: .destructive) {
                Task { try? await delete() }
            }
        }
    }

    private func saveChanges() async {
        var updated = collection
        updated.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.isPublic = isPublic
        isSaving = true
        defer { isSaving = false }
        try? await save(updated)
    }
}
