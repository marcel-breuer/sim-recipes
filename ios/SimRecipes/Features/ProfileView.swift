import AuthenticationServices
import SwiftUI

struct ProfileView: View {
    @ObservedObject var authService: AuthService
    @State private var errorMessage: String?

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
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Welcome, \(authService.session?.user.name ?? "Photographer")",
                systemImage: "person.crop.circle.fill",
                description: Text("Your profile and published recipes will appear here.")
            )

            Button("Sign Out", role: .destructive) {
                Task { @MainActor in
                    do {
                        try await authService.logout()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }
}
