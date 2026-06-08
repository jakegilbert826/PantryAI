import Foundation

/// A recipe row (Supabase `recipe`, design §7.2). Remote-only — the catalogue
/// stays in Supabase and is matched via the `match_recipes` RPC; the device
/// caches only match *results*, never the full table.
struct Recipe: Decodable, Identifiable, Hashable {
    let id: UUID
    let name: String
    let imageURL: String?
    let instructionsMD: String?
    let servings: Int?
    let cuisine: String?
    let totalTimeMin: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, servings, cuisine
        case imageURL = "image_url"
        case instructionsMD = "instructions_md"
        case totalTimeMin = "total_time_min"
    }
}

/// One ingredient line of a recipe (Supabase `recipe_ingredient`, design §7.2).
/// Keyed on `canonical_name` — the universal join key shared with the pantry —
/// which is what makes exact, embedding-free recipe matching possible (§8).
struct RecipeIngredient: Decodable, Hashable {
    let recipeID: UUID
    let canonicalName: String
    let quantity: Double?
    let measureUnit: MeasureUnit?
    /// Optional ingredients (garnish, "to taste") are ignored by coverage.
    let isOptional: Bool
    /// Core ingredients define the dish; only these drive coverage scoring.
    let isCore: Bool

    enum CodingKeys: String, CodingKey {
        case recipeID = "recipe_id"
        case canonicalName = "canonical_name"
        case quantity
        case measureUnit = "measure_unit"
        case isOptional = "is_optional"
        case isCore = "is_core"
    }
}
