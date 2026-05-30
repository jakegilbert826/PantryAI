import XCTest
@testable import PantryAI

@MainActor
final class InventoryItemTests: XCTestCase {

    override func setUp() {
        super.setUp()
        // currentConfidence reads the shared household size — pin it.
        UserPreferences.shared.householdSize = 1
    }

    func testResolvedModelUsesCategoryDefaultWhenNoOverride() {
        let item = InventoryItem(name: "Rice", category: .dryGoods, lastScanConfidence: 1.0)
        XCTAssertEqual(item.decayModel.modelIdentifier, "linear")
    }

    func testResolvedModelHonoursValidOverride() {
        let item = InventoryItem(
            name: "Rice", category: .dryGoods,
            lastScanConfidence: 1.0, decayModelOverride: "exponential"
        )
        XCTAssertEqual(item.decayModel.modelIdentifier, "exponential")
    }

    func testInvalidOverrideFallsBackToCategoryDefault() {
        let item = InventoryItem(
            name: "Rice", category: .dryGoods,
            lastScanConfidence: 1.0, decayModelOverride: "bogus"
        )
        XCTAssertEqual(item.decayModel.modelIdentifier, "linear")
    }

    func testCurrentConfidenceIsFreshRightAfterScan() {
        let item = InventoryItem(
            name: "Rice", category: .dryGoods,
            lastScanConfidence: 1.0, lastScanDate: .now
        )
        XCTAssertEqual(item.currentConfidence, 1.0, accuracy: 0.01)
    }

    func testIsLowAndIsExpiringForDepletedItem() {
        let item = InventoryItem(
            name: "Milk", category: .dairy,
            lastScanConfidence: 1.0, lastScanDate: .daysAgo(10_000)
        )
        XCTAssertEqual(item.currentConfidence, 0.0, accuracy: 0.0001)
        XCTAssertTrue(item.isLow)
        XCTAssertTrue(item.isExpiring)
    }

    func testFreshItemIsNeitherLowNorExpiring() {
        let item = InventoryItem(
            name: "Rice", category: .dryGoods,
            lastScanConfidence: 1.0, lastScanDate: .now
        )
        XCTAssertFalse(item.isLow)
        XCTAssertFalse(item.isExpiring)
    }

    func testExpiringThresholdIsWiderThanLowThreshold() {
        // An item between 0.25 and 0.40 confidence is expiring but not low.
        // dairy half-life 7 → linear total life 14 days; 9 days ≈ 0.357.
        let item = InventoryItem(
            name: "Yoghurt", category: .dairy,
            lastScanConfidence: 1.0, lastScanDate: .daysAgo(9)
        )
        XCTAssertEqual(item.currentConfidence, 0.357, accuracy: 0.02)
        XCTAssertTrue(item.isExpiring)
        XCTAssertFalse(item.isLow)
    }

    func testInventoryItemCodableRoundTrip() throws {
        let original = InventoryItem(
            name: "Olive Oil", category: .condiments, brand: "Acme",
            quantity: 0.5, unit: "ml", lastScanConfidence: 0.9,
            lastScanDate: Date(timeIntervalSince1970: 1_700_000_000),
            decayModelOverride: "exponential",
            usageHistory: [UsageEvent(itemID: UUID(), quantityUsed: 0.1)],
            imageURL: "https://example.com/oil.jpg"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InventoryItem.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testScannedItemDefaultsToIncluded() {
        let scanned = ScannedItem(
            name: "Eggs", category: .dairy, brand: nil,
            quantity: 1.0, unit: "units", confidence: 0.8
        )
        XCTAssertTrue(scanned.include)
    }
}
