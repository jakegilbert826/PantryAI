import XCTest
import SwiftData
@testable import PantryAI

@MainActor
final class RecipesViewModelTests: XCTestCase {

    private var context: ModelContext!
    private var gemini: MockGeminiService!

    override func setUp() {
        super.setUp()
        ["recipes.suggestions", "recipes.cacheKey", "recipes.detailCache"].forEach {
            UserDefaults.standard.removeObject(forKey: $0)
        }
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
        try seed([InventoryItem(name: "Rice", foodCategory: .dryGoods, measureConfidence: 1.0)])
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
            InventoryItem(name: "Fresh", foodCategory: .dryGoods,
                          measureConfidence: 1.0, lastScannedAt: .now),
            InventoryItem(name: "Expiring", foodCategory: .freshProduce,
                          measureConfidence: 1.0, lastScannedAt: .daysAgo(10)),
        ])
        let vm = RecipesViewModel(context: context, gemini: gemini)
        vm.preferExpiringSoon = true
        await vm.refresh()

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

    // MARK: - Caching

    func testRefreshReturnsCachedSuggestionsWhenInventoryUnchanged() async throws {
        gemini.recipeResult = [
            RecipeSuggestion(name: "Pasta", coveragePercent: 80,
                             missingIngredients: [], requiredIngredients: ["pasta"]),
        ]
        try seed([InventoryItem(name: "Pasta", foodCategory: .dryGoods, measureConfidence: 1.0)])
        let vm = RecipesViewModel(context: context, gemini: gemini)

        await vm.refresh()
        XCTAssertEqual(gemini.recipeCallCount, 1)

        await vm.refresh()
        XCTAssertEqual(gemini.recipeCallCount, 1, "second refresh with unchanged inventory should use cache")
        XCTAssertEqual(vm.suggestions.count, 1)
    }

    func testForceRefreshBypassesCache() async throws {
        gemini.recipeResult = [
            RecipeSuggestion(name: "Pasta", coveragePercent: 80,
                             missingIngredients: [], requiredIngredients: ["pasta"]),
        ]
        try seed([InventoryItem(name: "Pasta", foodCategory: .dryGoods, measureConfidence: 1.0)])
        let vm = RecipesViewModel(context: context, gemini: gemini)

        await vm.refresh()
        await vm.refresh(force: true)
        XCTAssertEqual(gemini.recipeCallCount, 2, "force refresh must call Gemini even if inventory unchanged")
    }

    func testStreamDetailReturnsCachedTextOnSecondCall() async throws {
        gemini.detailTokens = ["Step 1. ", "Step 2."]
        let vm = RecipesViewModel(context: context, gemini: gemini)
        let suggestion = RecipeSuggestion(name: "Omelette", coveragePercent: 100,
                                          missingIngredients: [], requiredIngredients: [])

        var first = ""
        for try await token in try await vm.streamDetail(for: suggestion) { first += token }

        var second = ""
        for try await token in try await vm.streamDetail(for: suggestion) { second += token }

        XCTAssertEqual(gemini.detailCallCount, 1, "second call for same recipe must not hit Gemini")
        XCTAssertEqual(first, second)
    }
}
