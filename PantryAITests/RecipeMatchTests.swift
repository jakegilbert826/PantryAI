import XCTest
import SwiftData
@testable import PantryAI

@MainActor
final class RecipeMatchTests: XCTestCase {

    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        context = TestModelContainer.make()
        ConsumptionRateCache.shared.reset()
    }

    override func tearDown() {
        context = nil
        super.tearDown()
    }

    @discardableResult
    private func makeItem(
        name: String,
        canonicalName: String? = nil,
        quantity: Double? = nil,
        halfLifeDays: Double?? = nil,
        lastScannedAt: Date? = nil
    ) -> InventoryItem {
        let item = InventoryItem(
            name: name,
            canonicalName: canonicalName,
            foodCategory: .dryGoods,
            measureUnit: .unit,
            quantity: quantity,
            halfLifeDays: halfLifeDays,
            lastScannedAt: lastScannedAt
        )
        context.insert(item)
        return item
    }

    // MARK: - AvailableSet (§8 threshold filter)

    func testAvailableSetIncludesItemsAboveThreshold() {
        // Shelf-stable (infinite half-life), amount unknown → confidence 1.0.
        makeItem(name: "Rice", halfLifeDays: .some(nil))
        makeItem(name: "Beans", halfLifeDays: .some(nil))

        let names = AvailableSet.canonicalNames(from: try! InventoryService(context: context).all())
        XCTAssertEqual(Set(names), ["Rice", "Beans"])
    }

    func testAvailableSetExcludesExpiredLowConfidenceItems() {
        // Short half-life observed long ago → presence collapses below τ.
        makeItem(name: "Spinach", halfLifeDays: .some(3), lastScannedAt: .daysAgo(30))

        let names = AvailableSet.canonicalNames(from: try! InventoryService(context: context).all())
        XCTAssertTrue(names.isEmpty)
    }

    func testAvailableSetDeduplicatesByCanonicalName() {
        makeItem(name: "Brown Onion", canonicalName: "onion", halfLifeDays: .some(nil))
        makeItem(name: "Red Onion", canonicalName: "onion", halfLifeDays: .some(nil))

        let names = AvailableSet.canonicalNames(from: try! InventoryService(context: context).all())
        XCTAssertEqual(names, ["onion"])
    }

    func testAvailableSetExcludesRemovedItems() throws {
        let milk = makeItem(name: "Milk", halfLifeDays: .some(nil))
        try InventoryService(context: context).delete(id: milk.id)

        // `all()` already filters removed; the guard is defence in depth.
        let names = AvailableSet.canonicalNames(from: [milk])
        XCTAssertTrue(names.isEmpty)
    }

    func testCustomThresholdIsRespected() {
        // Half-life 10d, ~6.6d elapsed → presence ≈ 0.63: above 0.5, below 0.7.
        makeItem(name: "Yoghurt", halfLifeDays: .some(10), lastScannedAt: .daysAgo(6.6))
        let items = try! InventoryService(context: context).all()

        XCTAssertEqual(AvailableSet.canonicalNames(from: items, threshold: 0.5), ["Yoghurt"])
        XCTAssertTrue(AvailableSet.canonicalNames(from: items, threshold: 0.7).isEmpty)
    }

    // MARK: - RecipeMatch decoding (RPC result, §8)

    func testRecipeMatchDecodesRPCRow() throws {
        let json = """
        [
          {
            "recipe_id": "11111111-1111-1111-1111-111111111111",
            "name": "Dal Tadka",
            "image_url": "https://img/dal.jpg",
            "servings": 4,
            "cuisine": "Indian",
            "total_time_min": 35,
            "core_total": 5,
            "core_matched": 4,
            "coverage": 0.8,
            "missing_core": ["cumin"]
          }
        ]
        """.data(using: .utf8)!

        let matches = try JSONDecoder().decode([RecipeMatch].self, from: json)
        XCTAssertEqual(matches.count, 1)
        let m = matches[0]
        XCTAssertEqual(m.name, "Dal Tadka")
        XCTAssertEqual(m.coreTotal, 5)
        XCTAssertEqual(m.coreMatched, 4)
        XCTAssertEqual(m.coverage, 0.8, accuracy: 1e-9)
        XCTAssertEqual(m.missingCore, ["cumin"])
        XCTAssertEqual(m.id, m.recipeID)
        XCTAssertFalse(m.isComplete)
    }

    func testRecipeMatchIsCompleteWhenAllCoreCovered() throws {
        let json = """
        [{
          "recipe_id": "22222222-2222-2222-2222-222222222222",
          "name": "Buttered Toast", "image_url": null,
          "servings": 1, "cuisine": null, "total_time_min": 5,
          "core_total": 2, "core_matched": 2, "coverage": 1.0, "missing_core": []
        }]
        """.data(using: .utf8)!

        let m = try JSONDecoder().decode([RecipeMatch].self, from: json)[0]
        XCTAssertTrue(m.isComplete)
        XCTAssertTrue(m.missingCore.isEmpty)
        XCTAssertNil(m.cuisine)
        XCTAssertNil(m.imageURL)
    }

    // MARK: - Recipe / RecipeIngredient decoding (§7.2)

    func testRecipeAndIngredientDecode() throws {
        let recipeJSON = """
        {
          "id": "33333333-3333-3333-3333-333333333333",
          "name": "Omelette", "image_url": null,
          "instructions_md": "Beat eggs...", "servings": 2,
          "cuisine": "French", "total_time_min": 10
        }
        """.data(using: .utf8)!
        let recipe = try JSONDecoder().decode(Recipe.self, from: recipeJSON)
        XCTAssertEqual(recipe.name, "Omelette")
        XCTAssertEqual(recipe.instructionsMD, "Beat eggs...")

        let ingJSON = """
        {
          "recipe_id": "33333333-3333-3333-3333-333333333333",
          "canonical_name": "egg", "quantity": 3, "measure_unit": "unit",
          "is_optional": false, "is_core": true
        }
        """.data(using: .utf8)!
        let ing = try JSONDecoder().decode(RecipeIngredient.self, from: ingJSON)
        XCTAssertEqual(ing.canonicalName, "egg")
        XCTAssertEqual(ing.measureUnit, .unit)
        XCTAssertTrue(ing.isCore)
        XCTAssertFalse(ing.isOptional)
    }

    // MARK: - RecipeMatchService short-circuit

    func testMatchServiceReturnsEmptyForEmptyAvailableSet() async throws {
        let result = try await RecipeMatchService.shared.match(available: [])
        XCTAssertTrue(result.isEmpty)
    }
}
