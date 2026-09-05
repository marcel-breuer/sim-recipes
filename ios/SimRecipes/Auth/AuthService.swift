import AuthenticationServices
import Combine
import Foundation
import Security

protocol CredentialStore {
    func read() throws -> Data?
    func write(_ data: Data) throws
    func delete() throws
}

enum CredentialStoreError: Error {
    case keychain(OSStatus)
}

final class KeychainCredentialStore: CredentialStore {
    private let service: String
    private let account = "auth-session"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.simrecipes.app") {
        self.service = service
    }

    func read() throws -> Data? {
        var result: AnyObject?
        let status = SecItemCopyMatching(query(returningData: true) as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError.keychain(status)
        }
    }

    func write(_ data: Data) throws {
        let query = query(returningData: false)
        let attributes: [CFString: Any] = [
            kSecValueData: data,
            kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError.keychain(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialStoreError.keychain(updateStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(query(returningData: false) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.keychain(status)
        }
    }

    private func query(returningData: Bool) -> [CFString: Any] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account
        ]
        if returningData {
            query[kSecReturnData] = true
            query[kSecMatchLimit] = kSecMatchLimitOne
        }
        return query
    }
}

@MainActor
final class AuthService: ObservableObject {
    @Published private(set) var session: AuthSession?

    private let apiClient: any APIClient
    private let credentialStore: any CredentialStore
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        apiClient: any APIClient,
        credentialStore: any CredentialStore = KeychainCredentialStore()
    ) {
        self.apiClient = apiClient
        self.credentialStore = credentialStore
        restoreSession()
    }

    func restoreSession() {
        guard
            let data = try? credentialStore.read(),
            let restoredSession = try? decoder.decode(AuthSession.self, from: data),
            restoredSession.expiresAt.map({ $0 > Date() }) ?? true
        else {
            session = nil
            try? credentialStore.delete()
            return
        }

        session = restoredSession
    }

    func authenticatedAPIClient() -> (any APIClient)? {
        guard let token = session?.token else {
            return nil
        }

        return BearerAPIClient(apiClient: apiClient, accessToken: token)
    }

    func signIn(with credential: ASAuthorizationAppleIDCredential) async throws {
        guard
            let identityToken = credential.identityToken,
            let identityTokenString = String(data: identityToken, encoding: .utf8)
        else {
            throw AuthServiceError.missingAppleIdentityToken
        }

        let requestBody = AppleLoginPayload(
            identityToken: identityTokenString,
            name: displayName(from: credential.fullName)
        )
        let request = APIRequest(
            method: .post,
            path: "auth/apple",
            body: try encoder.encode(requestBody)
        )
        let response = try await apiClient.send(
            request,
            responseType: APIResponse<AuthSession>.self
        )

        try credentialStore.write(encoder.encode(response.data))
        session = response.data
    }

    func logout() async throws {
        defer {
            session = nil
            try? credentialStore.delete()
        }

        guard let token = session?.token else {
            return
        }

        let request = APIRequest(
            method: .post,
            path: "auth/logout",
            headers: ["Authorization": "Bearer \(token)"]
        )
        _ = try await apiClient.send(
            request,
            responseType: APIResponse<LogoutResponse>.self
        )
    }

    private func displayName(from components: PersonNameComponents?) -> String? {
        guard let components else {
            return nil
        }

        let name = [components.givenName, components.familyName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return name.isEmpty ? nil : name
    }
}

enum AuthServiceError: LocalizedError {
    case missingAppleIdentityToken

    var errorDescription: String? {
        switch self {
        case .missingAppleIdentityToken:
            "Apple did not provide an identity token."
        }
    }
}

struct LogoutResponse: Decodable {
    let loggedOut: Bool

    enum CodingKeys: String, CodingKey {
        case loggedOut = "logged_out"
    }
}
