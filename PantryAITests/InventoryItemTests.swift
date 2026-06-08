import XCTest
import SwiftData
@testable import PantryAI

@MainActor
final class InventoryItemTests: XCTestCase {

    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        context = TestModelContainer.make()
    }

    override func tearDown() {
        context = nil
        super.tearDown()
    }

    @discardableResult
    private func makeItem(
        name: String = "Rice",
        foodCategory: FoodCategory = .dryGoods,
        measureUnit: MeasureUnit = .unit,
        quantity: Double? = nil,
        halfLifeDays: Double?? = nil,
        openedAt: Date? = nil,
        lastScannedAt: Date? = nil
    ) -> InventoryItem {
        let item = InventoryItem(
            name: name,
            foodCategory: foodCategory,
            measureUnit: measureUnit,
            quantity: quantity,
            halfLifeDays: halfLifeDays,
            openedAt: openedAt,
            lastScannedAt: lastScannedAt
        )
        context.insert(item)
        return item
    }

    // MARK: presence / spoilage

    func testFreshItemHasFullConfidence() {
        let item = makeItem(foodCategory: .dairy, lastScannedAt: .now)
        XCTAssertEqual(item.presenceConfidence(), 1.0, accuracy: 0.01)
        XCTAssertEqual(item.currentConfidence, 1.0, accuracy: 0.01)
    }

    func testPerishablePresenceHalvesAtHalfLife() {
        // dairy cold-start sealed half-life = 7 days
        let item = makeItem(foodCategory: .dairy, lastScannedAt: .daysAgo(7))
        XCTAssertEqual(item.presenceConfidence(), 0.5, accuracy: 0.02)
    }

    func testShelfStableSealedNeverDecays() {
        // dryGoods has a nil (infinite) sealed half-life
        let item = makeItem(foodCategory: .dryGoods, lastScannedAt: .daysAgo(1000))
        XCTAssertNil(item.effectiveHalfLife())
        XCTAssertEqual(item.presenceConfidence(), 1.0, accuracy: 0.0001)
    }

    func testOpenedShelfStableDoesDecay() {
        // Once opened, dryGoods uses its finite opened half-life (60 days)
        let item = makeItem(foodCategory: .dryGoods, openedAt: .daysAgo(60), lastScannedAt: .daysAgo(60))
        XCTAssertTrue(item.isOpened)
        XCTAssertEqual(item.effectiveHalfLife() ?? 0, 60, accuracy: 0.001)
        XCTAssertEqual(item.presenceConfidence(), 0.5, accuracy: 0.02)
    }

    func testDepletedPerishableIsLowAndExpiring() {
        let item = makeItem(foodCategory: .dairy, lastScannedAt: .daysAgo(10_000))
        XCTAssertEqual(item.currentConfidence, 0.0, accuracy: 0.0001)
        XCTAssertTrue(item.isLow)
        XCTAssertTrue(item.isExpiring)
    }

    func testFreshItemIsNeitherLowNorExpiring() {
        let item = makeItem(foodCategory: .dairy, lastScannedAt: .now)
        XCTAssertFalse(item.isLow)
        XCTAssertFalse(item.isExpiring)
    }

    // MARK: quantity

    func testUnknownQuantityDoesNotPenaliseConfidence() {
        // No quantity ever observed → availabilityQuantity is 1, presence carries.
        let item = makeItem(foodCategory: .dairy, quantity: nil, lastScannedAt: .now)
        XCTAssertNil(item.quantityMeanDisplay)
        XCTAssertFalse(item.hasAmount)
        XCTAssertEqual(item.availabilityQuantity(), 1.0, accuracy: 0.0001)
    }

    func testKnownQuantityIsAvailableWellAboveZero() {
        let item = makeItem(measureUnit: .g, quantity: 500, lastScannedAt: .now)
        XCTAssertEqual(item.quantityMeanDisplay ?? 0, 500, accuracy: 0.001)
        XCTAssertTrue(item.hasAmount)
        XCTAssertGreaterThan(item.availabilityQuantity(), 0.95)
    }

    // MARK: read-time math

    func testGaussianAvailabilityIsHalfAtMean() {
        XCTAssertEqual(GaussianMath.availability(value: 0, threshold: 0, sd: 10), 0.5, accuracy: 0.001)
    }

    // MARK: ScannedItem

    func testScannedItemDefaultsToIncluded() {
        let scanned = ScannedItem(
            name: "Eggs", canonicalName: "egg", foodCategory: .dairy, brandName: nil,
            measureValue: 1.0, measureUnit: .unit, confidence: 0.8
        )
        XCTAssertTrue(scanned.include)
    }

    // MARK: ObservationEngine

    func testStockObservationReanchorsAndLogs() {
        let item = makeItem(measureUnit: .g, quantity: nil, lastScannedAt: .daysAgo(3))
        let engine = ObservationEngine(context: context)
        engine.record(.userStock(420), on: item)

        XCTAssertEqual(item.lastObservedQuantity ?? 0, 420, accuracy: 0.001)
        XCTAssertEqual(item.quantityMeanDisplay ?? 0, 420, accuracy: 0.001)
        XCTAssertEqual(item.quantityLog.count, 1)
        XCTAssertEqual(item.quantityLog.first?.observationKind, .stock)
        XCTAssertEqual(item.lastObservedAt.timeIntervalSinceNow, 0, accuracy: 2)
    }

    func testInflowAddsToCurrentAmount() {
        let item = makeItem(measureUnit: .g, quantity: 200, lastScannedAt: .now)
        let engine = ObservationEngine(context: context)
        engine.record(InventoryObservation(kind: .inflow, quantity: 300,
                                           source: .orderImport, measurementConfidence: 0.9), on: item)
        XCTAssertEqual(item.lastObservedQuantity ?? 0, 500, accuracy: 0.001)
    }

    func testNonDetectionSoftlyReducesPresence() {
        let item = makeItem(foodCategory: .dryGoods, lastScannedAt: .now)
        XCTAssertEqual(item.presenceConfidence(), 1.0, accuracy: 0.001)
        let engine = ObservationEngine(context: context)
        engine.record(InventoryObservation(kind: .nonDetection, source: .scan,
                                           measurementConfidence: 0.5), on: item)
        // 1.0 × (1 − 0.3) = 0.7, infinite half-life so it stays put.
        XCTAssertEqual(item.presenceAnchor, 0.7, accuracy: 0.001)
        XCTAssertEqual(item.presenceConfidence(), 0.7, accuracy: 0.001)
    }

    func testObservationCreatesConsumptionProfile() {
        let item = makeItem(measureUnit: .g, quantity: 100)
        let engine = ObservationEngine(context: context)
        engine.record(.userStock(80), on: item)
        let profiles = try? context.fetch(FetchDescriptor<ConsumptionProfile>())
        XCTAssertEqual(profiles?.first?.canonicalName, item.canonicalName)
        XCTAssertEqual(profiles?.first?.observationCount, 1)
    }
}
