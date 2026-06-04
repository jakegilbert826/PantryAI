import XCTest
import SwiftData
@testable import PantryAI

@MainActor
final class InventoryItemTests: XCTestCase {

    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        context = TestModelContainer.make()
        UserPreferences.shared.householdSize = 1
    }

    override func tearDown() {
        context = nil
        super.tearDown()
    }

    private func makeItem(
        name: String = "Rice",
        foodCategory: FoodCategory = .dryGoods,
        measureConfidence: Double = 1.0,
        lastScannedAt: Date? = nil,
        decayRateOverride: Double? = nil
    ) -> InventoryItem {
        let item = InventoryItem(
            name: name,
            foodCategory: foodCategory,
            measureConfidence: measureConfidence,
            decayRateOverride: decayRateOverride,
            lastScannedAt: lastScannedAt
        )
        context.insert(item)
        return item
    }

    func testDefaultDecayModelWithNoRateOverride() {
        let item = makeItem(foodCategory: .dryGoods)
        XCTAssertEqual(item.decayModel.modelIdentifier, "linear")
    }

    func testFreshProduceUsesExponentialByDefault() {
        let item = makeItem(foodCategory: .freshProduce)
        XCTAssertEqual(item.decayModel.modelIdentifier, "exponential")
    }

    func testDecayRateOverridePreservesModelTypeForCategory() {
        // Override changes half-life, not model type
        let item = makeItem(foodCategory: .dryGoods, decayRateOverride: 30.0)
        XCTAssertEqual(item.decayModel.modelIdentifier, "linear")
    }

    func testCurrentConfidenceIsFreshRightAfterScan() {
        let item = makeItem(measureConfidence: 1.0, lastScannedAt: .now)
        XCTAssertEqual(item.currentConfidence, 1.0, accuracy: 0.01)
    }

    func testIsLowAndIsExpiringForDepletedItem() {
        let item = makeItem(
            foodCategory: .dairy,
            measureConfidence: 1.0,
            lastScannedAt: .daysAgo(10_000)
        )
        XCTAssertEqual(item.currentConfidence, 0.0, accuracy: 0.0001)
        XCTAssertTrue(item.isLow)
        XCTAssertTrue(item.isExpiring)
    }

    func testFreshItemIsNeitherLowNorExpiring() {
        let item = makeItem(measureConfidence: 1.0, lastScannedAt: .now)
        XCTAssertFalse(item.isLow)
        XCTAssertFalse(item.isExpiring)
    }

    func testExpiringThresholdIsWiderThanLowThreshold() {
        // dairy half-life 7 → linear total life 14 days; 9 days ≈ 0.357
        let item = makeItem(
            name: "Yoghurt",
            foodCategory: .dairy,
            measureConfidence: 1.0,
            lastScannedAt: .daysAgo(9)
        )
        XCTAssertEqual(item.currentConfidence, 0.357, accuracy: 0.02)
        XCTAssertTrue(item.isExpiring)
        XCTAssertFalse(item.isLow)
    }

    func testScannedItemDefaultsToIncluded() {
        let scanned = ScannedItem(
            name: "Eggs", canonicalName: "egg", foodCategory: .dairy, brandName: nil,
            measureValue: 1.0, measureUnit: .unit, confidence: 0.8
        )
        XCTAssertTrue(scanned.include)
    }
}
