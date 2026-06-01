import Foundation

/// What the rest of the app sees. Concrete impl can route via FastAPI or talk
/// to Gemini directly — both must satisfy this surface.
protocol GeminiServiceProtocol {
    func scanInventory(imageData: Data) async throws -> [ScannedItem]
    func scanReceipt(imageData: Data) async throws -> [ScannedItem]
    func generateRecipes(
        inventory: [InventoryItem],
        preferences: [RecipePreferenceSnapshot]
    ) async throws -> [RecipeSuggestion]
    func streamRecipeDetail(
        recipe: String,
        inventory: [InventoryItem]
    ) async throws -> AsyncThrowingStream<String, Error>
    func streamChatRecipe(
        history: [ChatTurn],
        inventory: [InventoryItem]
    ) async throws -> AsyncThrowingStream<String, Error>
}

struct ChatTurn {
    enum Role { case user, model }
    let role: Role
    let text: String
}

struct RecipeSuggestion: Identifiable, Hashable, Codable {
    var id: UUID = UUID()
    var name: String
    var coveragePercent: Double
    var missingIngredients: [String]
    var requiredIngredients: [String]

    enum CodingKeys: String, CodingKey {
        case name, coveragePercent, missingIngredients, requiredIngredients
    }
}
