import XCTest
import SwiftData
@testable import PantryAI

@MainActor
final class RecipesViewModelTests: XCTestCase {

    private var context: ModelContext!
    private var gemini: MockGeminiService!

    override func setUp() {
        super.setUp()
        context = TestModelContainer.make()
        gemini = MockGeminiService()
        UserPreferences.shared.householdSize = 1
    }

    private func seed(_ items: [InventoryItem]) throws {
        try InventoryService(context: context).upsert(items)
    }

    func testRefreshPopulatesSuggestions() async throws {
        gemini.recipeResult = [
            RecipeSuggestion(name: "Fried Rice", coveragePercent: 90,
                             missingIngredients: [], requiredIngredients: ["rice"]),
        ]
        try seed([InventoryItem(name: "Rice", category: .dryGoods, lastScanConfidence: 1.0)])
        let vm = RecipesViewModel(context: context, gemini: gemini)
        await vm.refresh()

        XCTAssertEqual(vm.suggestions.count, 1)
        XCTAssertEqual(vm.suggestions.first?.name, "Fried Rice")
        XCTAssertFalse(vm.isLoading)
        XCTAssertNil(vm.error)
    }

    func testRefreshSurfacesError() async throws {
        gemini.recipeError = PantryError.missingAPIKey
        let vm = RecipesViewModel(context: context, gemini: gemini)
        await vm.refresh()
        XCTAssertEqual(vm.error, .missingAPIKey)
        XCTAssertFalse(vm.isLoading)
    }

    func testPreferExpiringSoonSortsInventoryByAscendingConfidence() async throws {
        try seed([
            InventoryItem(name: "Fresh", category: .dryGoods,
                          lastScanConfidence: 1.0, lastScanDate: .now),
            InventoryItem(name: "Expiring", category: .freshProduce,
                          lastScanConfidence: 1.0, lastScanDate: .daysAgo(10)),
        ])
        let vm = RecipesViewModel(context: context, gemini: gemini)
        vm.preferExpiringSoon = true
        await vm.refresh()

        // The mock records the inventory ordering it received.
        XCTAssertEqual(gemini.lastRecipeInventory.first?.name, "Expiring",
            "lowest-confidence item should be sent first")
    }

    func testPreferencesArePassedThroughToGemini() async throws {
        let pref = RecipePreference(recipeName: "Tacos", liked: true)
        context.insert(pref)
        try context.save()

        let vm = RecipesViewModel(context: context, gemini: gemini)
        await vm.refresh()

        XCTAssertEqual(gemini.lastRecipePreferences.map(\.recipeName), ["Tacos"])
        XCTAssertEqual(gemini.lastRecipePreferences.first?.liked, true)
    }

    func testStreamDetailYieldsTokensInOrder() async throws {
        gemini.detailTokens = ["Heat ", "the ", "pan."]
        let vm = RecipesViewModel(context: context, gemini: gemini)
        let suggestion = RecipeSuggestion(name: "Omelette", coveragePercent: 100,
                                          missingIngredients: [], requiredIngredients: [])
        var collected = ""
        for try await token in try await vm.streamDetail(for: suggestion) {
            collected += token
        }
        XCTAssertEqual(collected, "Heat the pan.")
        XCTAssertEqual(gemini.lastDetailRecipe, "Omelette")
    }
}
