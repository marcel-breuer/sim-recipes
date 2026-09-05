import Combine
import Foundation

@MainActor
final class ProfileService: ObservableObject {
    @Published private(set) var profile: ProfileTransport?
    @Published private(set) var isLoading = false

    private let authService: AuthService
    private let encoder = JSONEncoder()

    init(authService: AuthService) {
        self.authService = authService
    }

    func loadCurrentProfile() async throws {
        guard let apiClient = authService.authenticatedAPIClient() else {
            profile = nil
            return
        }

        isLoading = true
        defer { isLoading = false }
        let request = APIRequest(method: .get, path: "me/profile")
        let response = try await apiClient.send(
            request,
            responseType: APIResponse<ProfileTransport>.self
        )
        profile = response.data
    }

    func updateCurrentProfile(
        username: String,
        cameraModelID: String?,
        biography: String?
    ) async throws {
        guard let apiClient = authService.authenticatedAPIClient() else {
            return
        }

        isLoading = true
        defer { isLoading = false }
        let payload = ProfileUpdatePayload(
            username: username,
            cameraModelID: cameraModelID,
            biography: biography,
            removeProfileImage: false
        )
        let request = APIRequest(
            method: .patch,
            path: "me/profile",
            body: try encoder.encode(payload)
        )
        let response = try await apiClient.send(
            request,
            responseType: APIResponse<ProfileTransport>.self
        )
        profile = response.data
    }
}
