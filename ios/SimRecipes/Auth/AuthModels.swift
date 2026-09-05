import Foundation

struct AppleLoginPayload: Encodable, Sendable {
    let identityToken: String
    let name: String?

    enum CodingKeys: String, CodingKey {
        case identityToken = "identity_token"
        case name
    }
}

struct AuthenticatedUser: Codable, Equatable, Sendable {
    let id: String
    let name: String
    let email: String?
}

struct AuthSession: Codable, Equatable, Sendable {
    let token: String
    let expiresAt: Date?
    let user: AuthenticatedUser

    enum CodingKeys: String, CodingKey {
        case token
        case expiresAt = "expires_at"
        case user
    }
}
