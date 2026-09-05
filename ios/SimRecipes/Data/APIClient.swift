import Foundation

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct APIRequest: Sendable {
    let method: HTTPMethod
    let path: String
    let queryItems: [URLQueryItem]
    let headers: [String: String]
    let body: Data?

    init(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
    }

    func url(relativeTo baseURL: URL) throws -> URL {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        let url = components.reduce(baseURL) { partialURL, component in
            partialURL.appendingPathComponent(String(component))
        }

        guard var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw APIClientError.invalidURL
        }

        urlComponents.queryItems = queryItems.isEmpty ? nil : queryItems

        guard let resolvedURL = urlComponents.url else {
            throw APIClientError.invalidURL
        }

        return resolvedURL
    }
}

enum APIClientError: LocalizedError {
    case invalidURL
    case transport(Error)
    case invalidResponse
    case unauthorized(APIErrorPayload?)
    case forbidden(APIErrorPayload?)
    case validation(APIErrorPayload?)
    case server(statusCode: Int, payload: APIErrorPayload?)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "The API request URL is invalid."
        case let .transport(error):
            error.localizedDescription
        case .invalidResponse:
            "The API returned an invalid response."
        case .unauthorized:
            "The API request requires authentication."
        case .forbidden:
            "The authenticated user is not allowed to perform this request."
        case .validation:
            "The API rejected the request because its data was invalid."
        case let .server(statusCode, _):
            "The API request failed with status code \(statusCode)."
        case let .decoding(error):
            "The API response could not be decoded: \(error.localizedDescription)"
        }
    }
}

struct APIErrorPayload: Codable, Equatable, Sendable {
    let message: String?
    let errors: [String: [String]]?

    init(message: String? = nil, errors: [String: [String]]? = nil) {
        self.message = message
        self.errors = errors
    }
}

protocol APIClient {
    func send<Response: Decodable>(
        _ request: APIRequest,
        responseType: Response.Type
    ) async throws -> Response
}

final class URLSessionAPIClient: APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let accessToken: String?

    init(
        baseURL: URL,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder(),
        accessToken: String? = nil
    ) {
        self.baseURL = baseURL
        self.session = session
        self.decoder = decoder
        self.accessToken = accessToken
    }

    func send<Response: Decodable>(
        _ request: APIRequest,
        responseType: Response.Type
    ) async throws -> Response {
        let url = try request.url(relativeTo: baseURL)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")

        for (header, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: header)
        }

        if request.body != nil {
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        if let accessToken {
            urlRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        let data: Data
        let response: URLResponse

        do {
            (data, response) = try await session.data(for: urlRequest)
        } catch {
            throw APIClientError.transport(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIClientError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            let payload = try? decoder.decode(APIErrorPayload.self, from: data)
            switch httpResponse.statusCode {
            case 401:
                throw APIClientError.unauthorized(payload)
            case 403:
                throw APIClientError.forbidden(payload)
            case 422:
                throw APIClientError.validation(payload)
            default:
                throw APIClientError.server(statusCode: httpResponse.statusCode, payload: payload)
            }
        }

        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw APIClientError.decoding(error)
        }
    }
}
