import Foundation
#if canImport(Security)
import Security
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking // Linux CI type-checking only
#endif

/// Minimal JSON HTTP client for the (future) backend. All live services go through it.
/// Endpoints and payloads are the proposals documented in API_CONTRACT.md.
final class APIClient {
    enum Method: String { case get = "GET", post = "POST", put = "PUT", patch = "PATCH", delete = "DELETE" }

    let baseURL: URL
    private let session: URLSession
    private let tokenStore: TokenStore
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL, tokenStore: TokenStore, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
        self.tokenStore = tokenStore
        decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
    }

    func send<Response: Decodable>(_ method: Method, _ path: String, query: [String: String] = [:],
                                   as type: Response.Type = Response.self) async throws -> Response {
        try await perform(method, path, query: query, body: nil)
    }

    func send<Response: Decodable, Body: Encodable>(_ method: Method, _ path: String, query: [String: String] = [:],
                                                    body: Body, as type: Response.Type = Response.self) async throws -> Response {
        try await perform(method, path, query: query, body: try encoder.encode(body))
    }

    private func perform<Response: Decodable>(_ method: Method, _ path: String, query: [String: String],
                                              body: Data?) async throws -> Response {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ar", forHTTPHeaderField: "Accept-Language")
        if let token = tokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw AppError.offline
        }

        guard let http = response as? HTTPURLResponse else { throw AppError.unknown }
        switch http.statusCode {
        case 200..<300:
            if Response.self == Empty.self { return Empty() as! Response }
            return try decoder.decode(Response.self, from: data)
        case 401: throw AppError.unauthorized
        case 404: throw AppError.notFound
        case 409:
            let problem = try? decoder.decode(APIProblem.self, from: data)
            throw AppError.conflict(problem?.message ?? problem?.error ?? "")
        case 400, 403, 429:
            let problem = try? decoder.decode(APIProblem.self, from: data)
            throw AppError.server(problem?.message ?? problem?.error ?? "تعذّر التحقق من الرمز.")
        case 422:
            let problem = try? decoder.decode(APIProblem.self, from: data)
            if let fields = problem?.fields, !fields.isEmpty { throw AppError.validation(fields) }
            throw AppError.server(problem?.message ?? problem?.error ?? "تحققي من البيانات المدخلة.")
        default:
            let problem = try? decoder.decode(APIProblem.self, from: data)
            throw AppError.server(problem?.message ?? problem?.error ?? "خطأ في الخادم (\(http.statusCode))")
        }
    }

    /// Authenticated binary note photo persistence (separate from JSON note metadata).
    func attachment(_ fileName: String, upload bytes: Data? = nil) async throws -> Data? {
        guard let safe = fileName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              fileName.range(of: "^[A-Za-z0-9_-]{8,90}\\.jpg$", options: .regularExpression) != nil else {
            throw AppError.validation(["image": "اسم المرفق غير صالح"])
        }
        var request = URLRequest(url: baseURL.appendingPathComponent("me/note-attachments/" + safe))
        request.httpMethod = bytes == nil ? "GET" : "PUT"
        if let token = tokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let bytes {
            guard bytes.count <= 5_000_000 else { throw AppError.validation(["image":"الصورة أكبر من 5MB"]) }
            request.httpBody = bytes
            request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        }
        do {
            let (result, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AppError.unknown }
            if http.statusCode == 401 { throw AppError.unauthorized }
            if !(200...299).contains(http.statusCode) { throw AppError.server("تعذّر الوصول لمرفق الصورة") }
            return bytes == nil ? result : nil
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw AppError.offline
        }
    }

    /// Multipart PDF upload authenticated with the current Keychain access token.
    func uploadCV(_ data: Data, fileName: String) async throws {
        guard data.count <= 5_000_000, data.starts(with: Data("%PDF-".utf8)) else {
            throw AppError.validation(["cv": "الملف يجب أن يكون PDF وأقل من 5 MB"])
        }
        let boundary = "Expo2030-" + UUID().uuidString
        let safeName = fileName.replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(safeName)\"\r\nContent-Type: application/pdf\r\n\r\n".utf8)
        body.append(data)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: baseURL.appendingPathComponent("me/cv"))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = tokenStore.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body
        do {
            let (_, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw AppError.unknown }
            if http.statusCode == 401 { throw AppError.unauthorized }
            if !(200...299).contains(http.statusCode) { throw AppError.server("تعذّر رفع ملف PDF إلى الخادم") }
        } catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut].contains(error.code) {
            throw AppError.offline
        }
    }

    struct Empty: Codable {}
}

/// Error body proposed in API_CONTRACT.md («شكل الأخطاء»).
struct APIProblem: Decodable {
    var code: String?
    var message: String?
    var error: String? // Actual Flask error response is {"error":"..."}.
    var fields: [String: String]?
}

/// Persist access tokens in the device Keychain (not UserDefaults or source code).
/// Tokens are scoped to the installed app and cleared when the user signs out.
final class TokenStore {
    private let service = "expo2030.account.session"
    private let account = "access-token"
    private var _accessToken: String?
    var accessToken: String? {
        get { _accessToken }
        set { _accessToken = newValue; persist(newValue) }
    }
    var refreshToken: String? // Backend intentionally issues short-lived access tokens only.

    init() {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account,
                                    kSecReturnData as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
            let bytes = result as? Data {
            _accessToken = String(data: bytes, encoding: .utf8)
        }
        #endif
    }

    private func persist(_ token: String?) {
        #if canImport(Security)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        if let token, let bytes = token.data(using: .utf8) {
            var attributes = query
            attributes[kSecValueData as String] = bytes
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(attributes as CFDictionary, nil)
        }
        #endif
    }
}
