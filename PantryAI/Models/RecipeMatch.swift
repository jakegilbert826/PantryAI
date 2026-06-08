import Foundation

/// One ranked row from the `match_recipes` RPC (design §8). Coverage is the
/// fraction of the recipe's *core* ingredients you can currently cover (after
/// remote substitution expansion); `missingCore` lists the core ingredients you
/// still lack. Matching is exact canonical-coverage — no embeddings, no LLM,
/// zero per-query cost.
struct RecipeMatch: Decodable, Identifiable, Hashable {
    let recipeID: UUID
    let name: String
    let imageURL: String?
    let servings: Int?
    let cuisine: String?
    let totalTimeMin: Int?
    let coreTotal: Int
    let coreMatched: Int
    let coverage: Double
    let missingCore: [String]

    var id: UUID { recipeID }

    /// True when every core ingredient is covered — cookable right now.
    var isComplete: Bool { coreTotal > 0 && coreMatched == coreTotal }

    enum CodingKeys: String, CodingKey {
        case recipeID = "recipe_id"
        case name, cuisine, servings, coverage
        case imageURL = "image_url"
        case totalTimeMin = "total_time_min"
        case coreTotal = "core_total"
        case coreMatched = "core_matched"
        case missingCore = "missing_core"
    }
}
