import Foundation

/// Thin `URLSession` wrapper. JSON in, JSON out. All call sites use this so
/// host/path swapping (local FastAPI → remote prod) happens in one place.
actor NetworkService {
    static let shared = NetworkService()

    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 30
        cfg.timeoutIntervalForResource = 60
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    func get<T: Decodable>(_ path: String, as: T.Type) async throws -> T {
        let req = try build(path: path, method: "GET", body: nil as Empty?)
        return try await perform(req)
    }

    func post<Body: Encodable, T: Decodable>(_ path: String, body: Body, as: T.Type) async throws -> T {
        let req = try build(path: path, method: "POST", body: body)
        return try await perform(req)
    }

    func delete(_ path: String) async throws {
        let req = try build(path: path, method: "DELETE", body: nil as Empty?)
        _ = try await performRaw(req)
    }

    // MARK: helpers

    private struct Empty: Encodable {}

    private func build<Body: Encodable>(path: String, method: String, body: Body?) throws -> URLRequest {
        var components = URLComponents(url: AppConfig.baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        guard let url = components?.url else { throw PantryError.network("bad URL: \(path)") }

        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try encoder.encode(body)
        }
        return req
    }

    private func perform<T: Decodable>(_ req: URLRequest) async throws -> T {
        let data = try await performRaw(req)
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw PantryError.decoding(String(describing: error))
        }
    }

    private func performRaw(_ req: URLRequest) async throws -> Data {
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                throw PantryError.network("no HTTP response")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw PantryError.network("HTTP \(http.statusCode)")
            }
            return data
        } catch let err as PantryError {
            throw err
        } catch {
            if (error as NSError).code == NSURLErrorCannotConnectToHost ||
               (error as NSError).code == NSURLErrorNotConnectedToInternet {
                throw PantryError.backendOffline
            }
            throw PantryError.network(error.localizedDescription)
        }
    }
}
