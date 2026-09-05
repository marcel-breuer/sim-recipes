import Foundation
@testable import SimRecipes

final class StubAPIClient: APIClient {
    private var responses: [Any]
    private(set) var requests: [String] = []

    init(responses: [Any] = []) {
        self.responses = responses
    }

    func send<Response: Decodable>(
        _ request: APIRequest,
        responseType: Response.Type
    ) async throws -> Response {
        requests.append(request.path)
        guard !responses.isEmpty else {
            throw APIClientError.invalidResponse
        }

        let response = responses.removeFirst()
        guard let response = response as? Response else {
            throw APIClientError.decoding(
                NSError(domain: "StubAPIClient", code: 1, userInfo: nil)
            )
        }

        return response
    }
}

final class MemoryCredentialStore: CredentialStore {
    var data: Data?

    func read() throws -> Data? {
        data
    }

    func write(_ data: Data) throws {
        self.data = data
    }

    func delete() throws {
        data = nil
    }
}
