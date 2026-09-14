import Foundation

enum APIContract {
    static let version = "v1"
    static let health = "health"
    static let authApple = "auth/apple"
    static let cameras = "cameras"
    static let categories = "categories"
    static let recipes = "recipes"
}

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

struct APIRequest: Sendable {
    let method: HTTPMethod
    let path: String
    let queryItems: [URLQueryItem]
    let headers: [String: String]
    let body: Data?
    let contentType: String?

    init(
        method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem] = [],
        headers: [String: String] = [:],
        body: Data? = nil,
        contentType: String? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.headers = headers
        self.body = body
        self.contentType = contentType
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

struct MultipartFormDataBuilder: Sendable {
    let boundary: String
    private var body = Data()

    init(boundary: String = "Boundary-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    mutating func append(name: String, value: String) {
        appendHeader(name: name)
        body.append(Data(value.utf8))
        body.append(Data("\r\n".utf8))
    }

    mutating func appendJSON<T: Encodable>(name: String, value: T, encoder: JSONEncoder = JSONEncoder()) throws {
        append(name: name, value: String(data: try encoder.encode(value), encoding: .utf8) ?? "null")
    }

    mutating func appendFile(name: String, filename: String, mimeType: String, data: Data) {
        appendHeader(name: name, filename: filename, mimeType: mimeType)
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finalized() -> (data: Data, contentType: String) {
        var result = body
        result.append(Data("--\(boundary)--\r\n".utf8))
        return (result, "multipart/form-data; boundary=\(boundary)")
    }

    private mutating func appendHeader(name: String, filename: String? = nil, mimeType: String? = nil) {
        body.append(Data("--\(boundary)\r\n".utf8))
        if let filename, let mimeType {
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
            body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        } else {
            body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        }
    }
}

struct APIResponse<Payload: Decodable>: Decodable {
    let data: Payload
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

    func download(_ request: APIRequest) async throws -> Data
}

final class URLSessionAPIClient: APIClient {
    private let baseURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder
    private let accessToken: String?

    init(
        baseURL: URL,
        session: URLSession = .shared,
        decoder: JSONDecoder = .apiDefault,
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

        if let contentType = request.contentType {
            urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type")
        } else if request.body != nil {
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

    func download(_ request: APIRequest) async throws -> Data {
        let url = try request.url(relativeTo: baseURL)
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Accept")

        for (header, value) in request.headers {
            urlRequest.setValue(value, forHTTPHeaderField: header)
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

        return data
    }
}

final class BearerAPIClient: APIClient {
    private let apiClient: any APIClient
    private let accessToken: String

    init(apiClient: any APIClient, accessToken: String) {
        self.apiClient = apiClient
        self.accessToken = accessToken
    }

    func send<Response: Decodable>(
        _ request: APIRequest,
        responseType: Response.Type
    ) async throws -> Response {
        var headers = request.headers
        headers["Authorization"] = "Bearer \(accessToken)"
        let authenticatedRequest = APIRequest(
            method: request.method,
            path: request.path,
            queryItems: request.queryItems,
            headers: headers,
            body: request.body,
            contentType: request.contentType
        )

        return try await apiClient.send(authenticatedRequest, responseType: responseType)
    }

    func download(_ request: APIRequest) async throws -> Data {
        var headers = request.headers
        headers["Authorization"] = "Bearer \(accessToken)"
        let authenticatedRequest = APIRequest(
            method: request.method,
            path: request.path,
            queryItems: request.queryItems,
            headers: headers,
            body: request.body,
            contentType: request.contentType
        )

        return try await apiClient.download(authenticatedRequest)
    }
}

private extension JSONDecoder {
    static var apiDefault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let value = try decoder.singleValueContainer().decode(String.self)
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: value) {
                return date
            }

            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: try decoder.singleValueContainer(),
                    debugDescription: "Invalid ISO-8601 date."
                )
            }
            return date
        }
        return decoder
    }
}
