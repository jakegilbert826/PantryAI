import XCTest
import SwiftData
@testable import PantryAI

@MainActor
final class InventoryItemTests: XCTestCase {

    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        context = TestModelContainer.make()
        ConsumptionRateCache.shared.reset()   // isolate the process-wide cache
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

    // MARK: Phase 5 — quantity estimation

    func testEstimatorUsesStatedSizeExactly() {
        let ref = FoodReference(canonicalName: "baked_bean", displayName: "Baked Beans",
                                defaultMeasureUnit: .g, defaultStorageLocation: .pantry,
                                defaultPackagingCategory: .canned, defaultContainerSize: 415)
        let est = QuantityEstimator.estimate(statedSize: 500, count: 1, reference: ref)
        XCTAssertEqual(est.quantity, 500, accuracy: 0.001)
        XCTAssertFalse(est.assumedSize)
    }

    func testEstimatorAssumesContainerSizeWhenUnstated() {
        let ref = FoodReference(canonicalName: "baked_bean", displayName: "Baked Beans",
                                defaultMeasureUnit: .g, defaultStorageLocation: .pantry,
                                defaultPackagingCategory: .canned, defaultContainerSize: 415)
        let est = QuantityEstimator.estimate(count: 2, reference: ref)
        XCTAssertEqual(est.quantity, 830, accuracy: 0.001)
        XCTAssertTrue(est.assumedSize)
    }

    func testEstimatorFallsBackToBareCount() {
        let est = QuantityEstimator.estimate(count: 3, reference: nil)
        XCTAssertEqual(est.quantity, 3, accuracy: 0.001)
        XCTAssertTrue(est.assumedSize)
    }

    func testAssumedSizeInflatesInflowVariance() {
        let item = makeItem(measureUnit: .g, quantity: 0, lastScannedAt: .now)
        let engine = ObservationEngine(context: context)
        let ref = FoodReference(canonicalName: item.canonicalName, displayName: "Rice",
                                defaultMeasureUnit: .g, defaultStorageLocation: .pantry,
                                defaultPackagingCategory: .dried, defaultContainerSize: 1000)
        engine.record(.purchase(count: 1, reference: ref), on: item)
        XCTAssertEqual(item.lastObservedQuantity ?? 0, 1000, accuracy: 0.001)
        // assumed size → cv 0.30 → variance (0.30·1000)² = 90_000, well above floor.
        XCTAssertGreaterThan(item.observationVariance, 80_000)
    }

    // MARK: Phase 6 — online learning

    func testStockPairLearnsConsumptionRate() {
        // 1000 g → 800 g over 4 days ⇒ 50 g/day.
        let item = makeItem(measureUnit: .g, quantity: 1000, lastScannedAt: .daysAgo(4))
        let engine = ObservationEngine(context: context)
        engine.record(.userStock(800), on: item)
        let profile = try? context.fetch(FetchDescriptor<ConsumptionProfile>()).first
        XCTAssertEqual(profile?.consumptionRatePerDay ?? 0, 50, accuracy: 0.001)
    }

    func testRestockDoesNotLowerLearnedRate() {
        let item = makeItem(measureUnit: .g, quantity: 1000, lastScannedAt: .daysAgo(4))
        let engine = ObservationEngine(context: context)
        engine.record(.userStock(800), on: item)          // learns 50 g/day
        // A later reading that is *higher* (restock) must not feed a 0 sample.
        item.lastObservedAt = .daysAgo(2)
        engine.record(.userStock(900), on: item)
        let profile = try? context.fetch(FetchDescriptor<ConsumptionProfile>()).first
        XCTAssertEqual(profile?.consumptionRatePerDay ?? 0, 50, accuracy: 0.001)
    }

    func testPurchaseCadenceLearnsConsumptionRate() {
        let item = makeItem(measureUnit: .g, quantity: 0, lastScannedAt: .now)
        let engine = ObservationEngine(context: context)
        // First purchase seeds lastPurchaseAt; no interval yet.
        engine.record(InventoryObservation(kind: .inflow, quantity: 700,
                      source: .orderImport, measurementConfidence: 0.9, at: .daysAgo(7)), on: item)
        // Second purchase 7 days later ⇒ 700 g / 7 d = 100 g/day.
        engine.record(InventoryObservation(kind: .inflow, quantity: 700,
                      source: .orderImport, measurementConfidence: 0.9, at: .now), on: item)
        let profile = try? context.fetch(FetchDescriptor<ConsumptionProfile>()).first
        XCTAssertEqual(profile?.consumptionRatePerDay ?? 0, 100, accuracy: 0.001)
    }

    func testNearInstantStockReadDoesNotLearn() {
        let item = makeItem(measureUnit: .g, quantity: 1000, lastScannedAt: .now)
        let engine = ObservationEngine(context: context)
        engine.record(.userStock(900), on: item)   // ~0 days elapsed → gated out
        let profile = try? context.fetch(FetchDescriptor<ConsumptionProfile>()).first
        XCTAssertEqual(profile?.consumptionRatePerDay ?? 0, 0, accuracy: 0.001)
    }

    func testLearnedRateDecaysDisplayedQuantity() {
        // Learn 50 g/day, then read 2 days after the re-anchor: 800 − 50·2 = 700.
        let item = makeItem(measureUnit: .g, quantity: 1000, lastScannedAt: .daysAgo(4))
        let engine = ObservationEngine(context: context)
        engine.record(.userStock(800), on: item)
        item.lastObservedAt = .daysAgo(2)
        XCTAssertEqual(item.quantityMeanDisplay ?? 0, 700, accuracy: 0.1)
        XCTAssertEqual(item.consumptionParameters.rate, 50, accuracy: 0.001)
    }

    func testNoProfileMeansNoConsumptionDecay() {
        // No observation recorded → no profile → rate 0 → amount holds steady.
        let item = makeItem(measureUnit: .g, quantity: 500, lastScannedAt: .daysAgo(30))
        XCTAssertEqual(item.consumptionParameters, .none)
        XCTAssertEqual(item.quantityMeanDisplay ?? 0, 500, accuracy: 0.001)
    }

    func testCacheServesLearnedRateWithoutRefetch() {
        // After record(...) the cache holds the learned params; a read sees them
        // even though we never reload the cache from the store.
        let item = makeItem(measureUnit: .g, quantity: 1000, lastScannedAt: .daysAgo(4))
        let engine = ObservationEngine(context: context)
        engine.record(.userStock(800), on: item)   // learns 50 g/day, warms cache
        XCTAssertEqual(item.consumptionParameters.rate, 50, accuracy: 0.001)

        // A fresh cache (no warm entry) reloads from the persisted profile.
        ConsumptionRateCache.shared.reset()
        XCTAssertEqual(item.consumptionParameters.rate, 50, accuracy: 0.001)
    }
}
