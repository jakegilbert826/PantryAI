import Foundation
@testable import PantryAI

/// Test double for `GeminiServiceProtocol`. Records what it was asked and
/// returns canned responses (or throws) so view-model logic can be exercised
/// without any network or API key.
final class MockGeminiService: GeminiServiceProtocol, @unchecked Sendable {
    // Canned outputs
    var scanResult: [ScannedItem] = []
    var recipeResult: [RecipeSuggestion] = []
    var detailTokens: [String] = []

    // Error injection
    var scanError: Error?
    var recipeError: Error?
    var detailError: Error?

    // Captured inputs
    private(set) var scanCallCount = 0
    private(set) var recipeCallCount = 0
    private(set) var detailCallCount = 0
    private(set) var lastRecipeInventory: [InventoryItem] = []
    private(set) var lastRecipePreferences: [RecipePreferenceSnapshot] = []
    private(set) var lastDetailRecipe: String?

    func scanInventory(imageData: Data) async throws -> [ScannedItem] {
        scanCallCount += 1
        if let scanError { throw scanError }
        return scanResult
    }

    func generateRecipes(
        inventory: [InventoryItem],
        preferences: [RecipePreferenceSnapshot]
    ) async throws -> [RecipeSuggestion] {
        recipeCallCount += 1
        lastRecipeInventory = inventory
        lastRecipePreferences = preferences
        if let recipeError { throw recipeError }
        return recipeResult
    }

    func streamRecipeDetail(
        recipe: String,
        inventory: [InventoryItem]
    ) async throws -> AsyncThrowingStream<String, Error> {
        detailCallCount += 1
        lastDetailRecipe = recipe
        if let detailError { throw detailError }
        let tokens = detailTokens
        return AsyncThrowingStream { continuation in
            for token in tokens { continuation.yield(token) }
            continuation.finish()
        }
    }
}
