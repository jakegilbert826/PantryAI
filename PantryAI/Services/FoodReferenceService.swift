import Foundation

actor FoodReferenceService {
    static let shared = FoodReferenceService()

    private var cache: [String: FoodReference] = [:]

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .useDefaultKeys
        return d
    }()

    func prefetch() async {
        guard cache.isEmpty else { return }
        do {
            let rows = try await fetchAll()
            cache = Dictionary(uniqueKeysWithValues: rows.map { ($0.canonicalName, $0) })
        } catch {
            print("[FoodReferenceService] prefetch failed: \(error)")
        }
    }

    func lookup(canonicalName: String) -> FoodReference? {
        cache[canonicalName]
    }

    // MARK: - Private

    private func fetchAll() async throws -> [FoodReference] {
        var url = AppConfig.supabaseURL
            .appendingPathComponent("rest/v1/food_reference")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "select", value: "*")]
        guard let resolved = components?.url else {
            throw PantryError.network("bad Supabase URL")
        }

        var req = URLRequest(url: resolved)
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PantryError.network("Supabase HTTP error")
        }
        return try decoder.decode([FoodReference].self, from: data)
    }
}
