import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @ObservedObject var authService: AuthService
    @ObservedObject var profileService: ProfileService
    @State private var errorMessage: String?
    @State private var username = ""
    @State private var biography = ""
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
        }
    }

    private func loadProfile() async {
        guard authService.session != nil, !hasLoadedProfile else {
            return
        }

        do {
            try await profileService.loadCurrentProfile()
            username = profileService.profile?.username ?? ""
            biography = profileService.profile?.biography ?? ""
            hasLoadedProfile = true
        } catch let APIClientError.server(statusCode, _) where statusCode == 404 {
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
