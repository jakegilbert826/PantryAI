import Foundation

/// Calls the Supabase `match_recipes` RPC (design §8): sends the available
/// canonical names and gets back recipes ranked by core-ingredient coverage.
/// Recipes and substitution tables stay remote; only the ranked result set is
/// returned. Mirrors `FoodReferenceService`'s direct-to-Supabase request style
/// (the shared `NetworkService` targets the FastAPI base URL, not Supabase).
actor RecipeMatchService {
    static let shared = RecipeMatchService()

    private let decoder = JSONDecoder()   // explicit CodingKeys → no key strategy

    /// POSTs the available canonical names to `rest/v1/rpc/match_recipes` and
    /// returns recipes ranked by core coverage. An empty available set
    /// short-circuits to no matches — no point in a round-trip.
    func match(available: [String]) async throws -> [RecipeMatch] {
        guard !available.isEmpty else { return [] }

        let url = AppConfig.supabaseURL
            .appendingPathComponent("rest/v1/rpc/match_recipes")
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue(AppConfig.supabaseAnonKey, forHTTPHeaderField: "apikey")
        req.setValue("Bearer \(AppConfig.supabaseAnonKey)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: ["available": available])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw PantryError.network("Supabase match_recipes HTTP error")
        }
        do {
            return try decoder.decode([RecipeMatch].self, from: data)
        } catch {
            throw PantryError.decoding(String(describing: error))
        }
    }
}
