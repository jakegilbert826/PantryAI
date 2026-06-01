import XCTest
@testable import PantryAI

/// The network round-trip to Gemini can't run in unit tests (needs a key and a
/// live endpoint), but the deterministic prompt construction can — and it's
/// where the contract with the model lives.
@MainActor
final class GeminiPromptTests: XCTestCase {

    override func setUp() {
        super.setUp()
        UserPreferences.shared.householdSize = 1
    }

    func testScanPromptListsEveryCategoryRawValue() {
        let prompt = GeminiService.scanPrompt
        for category in FoodCategory.allCases {
            XCTAssertTrue(prompt.contains(category.rawValue),
                "scan prompt is missing category \(category.rawValue)")
        }
    }

    func testScanPromptAsksForJSONOnly() {
        XCTAssertTrue(GeminiService.scanPrompt.contains("JSON"))
    }

    func testRecipePromptEmbedsInventoryAndPreferencesAsJSON() {
        let inventory = [
            InventoryItem(name: "Rice", foodCategory: .dryGoods, measureConfidence: 1.0),
        ]
        let prefs = [RecipePreferenceSnapshot(recipeName: "Curry", liked: true)]
        let prompt = GeminiService.recipePrompt(inventory: inventory, preferences: prefs)

        XCTAssertTrue(prompt.contains("Rice"))
        XCTAssertTrue(prompt.contains("Curry"))
        XCTAssertTrue(prompt.contains("coveragePercent"))
    }

    func testRecipePromptHandlesEmptyInventoryGracefully() {
        let prompt = GeminiService.recipePrompt(inventory: [], preferences: [])
        XCTAssertTrue(prompt.contains("[]"))
    }

    func testRecipeDetailPromptNamesRecipeAndIncludesInventory() {
        let inventory = [
            InventoryItem(name: "Eggs", foodCategory: .dairy,
                          measureConfidence: 1.0, lastScannedAt: .now),
        ]
        let prompt = GeminiService.recipeDetailPrompt(recipe: "Shakshuka", inventory: inventory)
        XCTAssertTrue(prompt.contains("Shakshuka"))
        XCTAssertTrue(prompt.contains("Eggs"))
        XCTAssertTrue(prompt.contains("%"))
    }
}
