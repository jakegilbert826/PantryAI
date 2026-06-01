import XCTest
@testable import PantryAI

/// The app and the FastAPI backend exchange JSON. These tests lock the Swift-side
/// wire contract down so field renames don't silently break the API.
final class WireFormatTests: XCTestCase {

    private func backendDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func backendEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .convertToSnakeCase
        e.dateEncodingStrategy = .iso8601
        return e
    }

    func testBackendItemFromInventoryItemPreservesFields() {
        let item = InventoryItem(
            name: "Butter", brandName: "Kerry",
            foodCategory: .dairy,
            measureValue: 0.75, measureUnit: .g,
            measureConfidence: 0.9,
            decayRateOverride: nil
        )
        let wire = BackendInventoryItem(from: item)
        XCTAssertEqual(wire.id, item.id)
        XCTAssertEqual(wire.name, "Butter")
        XCTAssertEqual(wire.foodCategory, "dairy")
        XCTAssertEqual(wire.measureValue, 0.75)
        XCTAssertNil(wire.decayRateOverride)
    }

    func testBackendItemRoundTripsThroughModel() {
        let item = InventoryItem(
            name: "Spinach", foodCategory: .freshProduce,
            measureValue: 1.0, measureConfidence: 0.6
        )
        let restored = BackendInventoryItem(from: item).toModel()
        XCTAssertEqual(restored.name, item.name)
        XCTAssertEqual(restored.foodCategory, item.foodCategory)
        XCTAssertEqual(restored.measureValue, item.measureValue)
        XCTAssertEqual(restored.measureConfidence, item.measureConfidence)
    }

    func testBackendItemUnknownCategoryFallsBackToDryGoods() {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Mystery","food_category":"plutonium",
         "measure_value":1.0,"measure_unit":"unit","measure_confidence":0.5}
        """.data(using: .utf8)!
        let wire = try! backendDecoder().decode(BackendInventoryItem.self, from: json)
        XCTAssertEqual(wire.toModel().foodCategory, .dryGoods)
    }

    func testBackendItemDecodesSnakeCaseAndISO8601() throws {
        let original = BackendInventoryItem(from: InventoryItem(
            name: "Cheese", foodCategory: .dairy,
            measureConfidence: 0.8,
            lastScannedAt: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let data = try backendEncoder().encode(original)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("measure_confidence"))
        XCTAssertTrue(json.contains("last_scanned_at"))

        let decoded = try backendDecoder().decode(BackendInventoryItem.self, from: data)
        XCTAssertEqual(decoded.lastScannedAt, original.lastScannedAt)
    }

    func testRecipeSuggestionDecodesFromGeminiShape() throws {
        let json = """
        [{"name":"Omelette","coveragePercent":80,
          "missingIngredients":["chives"],
          "requiredIngredients":["eggs","butter","chives"]}]
        """.data(using: .utf8)!
        let suggestions = try JSONDecoder().decode([RecipeSuggestion].self, from: json)
        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions[0].name, "Omelette")
        XCTAssertEqual(suggestions[0].coveragePercent, 80)
        XCTAssertEqual(suggestions[0].missingIngredients, ["chives"])
    }
}
