import XCTest
@testable import PantryAI

/// The app and the FastAPI backend exchange JSON with snake_case keys and
/// ISO-8601 dates. These tests lock that contract down on the Swift side.
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
            name: "Butter", category: .dairy, brand: "Kerry",
            quantity: 0.75, unit: "g", lastScanConfidence: 0.9,
            decayModelOverride: "linear", imageURL: nil
        )
        let wire = BackendInventoryItem(from: item)
        XCTAssertEqual(wire.id, item.id)
        XCTAssertEqual(wire.name, "Butter")
        XCTAssertEqual(wire.category, "dairy")
        XCTAssertEqual(wire.quantity, 0.75)
        XCTAssertEqual(wire.decayModelOverride, "linear")
    }

    func testBackendItemRoundTripsThroughStruct() {
        let item = InventoryItem(
            name: "Spinach", category: .freshProduce,
            quantity: 1.0, lastScanConfidence: 0.6
        )
        let restored = BackendInventoryItem(from: item).toStruct()
        XCTAssertEqual(restored.name, item.name)
        XCTAssertEqual(restored.category, item.category)
        XCTAssertEqual(restored.quantity, item.quantity)
        XCTAssertEqual(restored.lastScanConfidence, item.lastScanConfidence)
        // The wire format does not carry usage history.
        XCTAssertTrue(restored.usageHistory.isEmpty)
    }

    func testBackendItemUnknownCategoryFallsBackToDryGoods() {
        let json = """
        {"id":"\(UUID().uuidString)","name":"Mystery","category":"plutonium",
         "quantity":1.0,"last_scan_confidence":0.5,
         "last_scan_date":"2026-01-01T00:00:00Z"}
        """.data(using: .utf8)!
        let wire = try! backendDecoder().decode(BackendInventoryItem.self, from: json)
        XCTAssertEqual(wire.toStruct().category, .dryGoods)
    }

    func testBackendItemDecodesSnakeCaseAndISO8601() throws {
        let original = BackendInventoryItem(from: InventoryItem(
            name: "Cheese", category: .dairy,
            lastScanConfidence: 0.8,
            lastScanDate: Date(timeIntervalSince1970: 1_700_000_000)
        ))
        let data = try backendEncoder().encode(original)
        let json = String(data: data, encoding: .utf8)!
        XCTAssertTrue(json.contains("last_scan_confidence"))
        XCTAssertTrue(json.contains("last_scan_date"))

        let decoded = try backendDecoder().decode(BackendInventoryItem.self, from: data)
        XCTAssertEqual(decoded.lastScanDate, original.lastScanDate)
    }

    func testUsageEventCodableRoundTrip() throws {
        let event = UsageEvent(itemID: UUID(), quantityUsed: 0.4, source: .recipeCooked)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(UsageEvent.self, from: data)
        XCTAssertEqual(decoded, event)
        XCTAssertEqual(decoded.source, .recipeCooked)
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
