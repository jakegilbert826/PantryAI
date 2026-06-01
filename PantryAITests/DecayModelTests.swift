import XCTest
@testable import PantryAI

final class DecayModelTests: XCTestCase {

    // MARK: Linear

    func testLinearAtScanTimeReturnsScanConfidence() {
        let model = LinearDecayModel(category: .dryGoods)
        let c = model.confidence(
            lastScanConfidence: 1.0,
            lastScanDate: .now,
            householdSize: 1,
            usageHistory: []
        )
        XCTAssertEqual(c, 1.0, accuracy: 0.001)
    }

    func testLinearReachesZeroAtEndOfLifeWindow() {
        // dryGoods half-life 180 → total linear life 360 days at household mult 1.0
        let model = LinearDecayModel(category: .dryGoods)
        let c = model.confidence(
            lastScanConfidence: 1.0,
            lastScanDate: .daysAgo(360),
            householdSize: 1,
            usageHistory: []
        )
        XCTAssertEqual(c, 0.0, accuracy: 0.001)
    }

    func testLinearMidpointIsHalfConfidence() {
        let model = LinearDecayModel(category: .dryGoods)
        let c = model.confidence(
            lastScanConfidence: 1.0,
            lastScanDate: .daysAgo(180),
            householdSize: 1,
            usageHistory: []
        )
        XCTAssertEqual(c, 0.5, accuracy: 0.01)
    }

    func testLinearNeverGoesNegative() {
        let model = LinearDecayModel(category: .meat)
        let c = model.confidence(
            lastScanConfidence: 1.0,
            lastScanDate: .daysAgo(10_000),
            householdSize: 1,
            usageHistory: []
        )
        XCTAssertEqual(c, 0.0, accuracy: 0.0001)
    }

    // MARK: Exponential

    func testExponentialHalvesEveryHalfLife() {
        // freshProduce half-life 5 days
        let model = ExponentialDecayModel(category: .freshProduce)
        let oneHalfLife = model.confidence(
            lastScanConfidence: 1.0,
            lastScanDate: .daysAgo(5),
            householdSize: 1,
            usageHistory: []
        )
        XCTAssertEqual(oneHalfLife, 0.5, accuracy: 0.01)

        let twoHalfLives = model.confidence(
            lastScanConfidence: 1.0,
            lastScanDate: .daysAgo(10),
            householdSize: 1,
            usageHistory: []
        )
        XCTAssertEqual(twoHalfLives, 0.25, accuracy: 0.01)
    }

    func testExponentialStaysAtScanValueAtTimeZero() {
        let model = ExponentialDecayModel(category: .snacks)
        let c = model.confidence(
            lastScanConfidence: 0.8,
            lastScanDate: .now,
            householdSize: 1,
            usageHistory: []
        )
        XCTAssertEqual(c, 0.8, accuracy: 0.001)
    }

    // MARK: Step

    func testStepHoldsFullValueBeforeDepletion() {
        // meat half-life 2 → depletion at 4 days (household mult 1.0)
        let model = StepDecayModel(category: .meat)
        let c = model.confidence(
            lastScanConfidence: 1.0,
            lastScanDate: .daysAgo(2),
            householdSize: 1,
            usageHistory: []
        )
        XCTAssertEqual(c, 1.0, accuracy: 0.001)
    }

    func testStepDropsToZeroAfterDepletion() {
        let model = StepDecayModel(category: .meat)
        let c = model.confidence(
            lastScanConfidence: 1.0,
            lastScanDate: .daysAgo(5),
            householdSize: 1,
            usageHistory: []
        )
        XCTAssertEqual(c, 0.0, accuracy: 0.001)
    }

    // MARK: Usage subtraction (shared helper)

    func testLoggedUsageSubtractsFromConfidence() {
        let model = LinearDecayModel(category: .dryGoods)
        let log = ItemQuantityLog(
            measureType: .count,
            measureValue: 0.3,
            measureUnit: .unit,
            measureConfidence: 1.0,
            source: .manual
        )
        let c = model.confidence(
            lastScanConfidence: 1.0,
            lastScanDate: .daysAgo(0.001),
            householdSize: 1,
            usageHistory: [log]
        )
        XCTAssertEqual(c, 0.7, accuracy: 0.01)
    }

    func testUsageBeforeLastScanIsIgnored() {
        let model = LinearDecayModel(category: .dryGoods)
        let log = ItemQuantityLog(
            recordedAt: .daysAgo(40),
            measureType: .count,
            measureValue: 0.9,
            measureUnit: .unit,
            measureConfidence: 1.0,
            source: .manual
        )
        let c = model.confidence(
            lastScanConfidence: 1.0,
            lastScanDate: .daysAgo(0.001),
            householdSize: 1,
            usageHistory: [log]
        )
        XCTAssertEqual(c, 1.0, accuracy: 0.01)
    }

    func testUsageCannotPushConfidenceNegative() {
        let model = LinearDecayModel(category: .dryGoods)
        let log = ItemQuantityLog(
            measureType: .count,
            measureValue: 5.0,
            measureUnit: .unit,
            measureConfidence: 1.0,
            source: .manual
        )
        let c = model.confidence(
            lastScanConfidence: 1.0,
            lastScanDate: .now,
            householdSize: 1,
            usageHistory: [log]
        )
        XCTAssertGreaterThanOrEqual(c, 0.0)
    }

    // MARK: Household multiplier

    func testHouseholdMultiplierIsOneForSinglePerson() {
        let model = LinearDecayModel(category: .dryGoods)
        XCTAssertEqual(model.householdMultiplier(1), 1.0, accuracy: 0.0001)
    }

    func testHouseholdMultiplierClampsZeroToOne() {
        let model = LinearDecayModel(category: .dryGoods)
        XCTAssertEqual(model.householdMultiplier(0), 1.0, accuracy: 0.0001)
    }

    func testLargerHouseholdDecaysFaster() {
        let model = ExponentialDecayModel(category: .freshProduce)
        let solo = model.confidence(
            lastScanConfidence: 1.0, lastScanDate: .daysAgo(5),
            householdSize: 1, usageHistory: []
        )
        let family = model.confidence(
            lastScanConfidence: 1.0, lastScanDate: .daysAgo(5),
            householdSize: 5, usageHistory: []
        )
        XCTAssertLessThan(family, solo)
    }

    // MARK: Output always bounded 0...1

    func testAllModelsStayWithinUnitInterval() {
        let categories = FoodCategory.allCases
        let models: [any DecayModel] = categories.map { DecayModelFactory.model(for: $0) }
        for model in models {
            for days in [0.0, 1, 7, 30, 365, 5000] {
                let c = model.confidence(
                    lastScanConfidence: 1.0,
                    lastScanDate: .daysAgo(days),
                    householdSize: 3,
                    usageHistory: []
                )
                XCTAssertGreaterThanOrEqual(c, 0.0, "\(model.modelIdentifier) @ \(days)d")
                XCTAssertLessThanOrEqual(c, 1.0, "\(model.modelIdentifier) @ \(days)d")
            }
        }
    }

    // MARK: Learned model

    func testLearnedFallsBackToLinearBelowThreshold() {
        let learned = LearnedDecayModel(category: .dryGoods)
        let linear = LinearDecayModel(category: .dryGoods)
        // 5 events before the scan date — don't subtract, just compare curve
        let usage = (0..<5).map { i in
            ItemQuantityLog(
                recordedAt: .daysAgo(Double(100 + i)),
                measureType: .count,
                measureValue: 0.1,
                measureUnit: .unit,
                measureConfidence: 1.0,
                source: .manual
            )
        }
        let scanDate = Date.daysAgo(30)
        let learnedC = learned.confidence(
            lastScanConfidence: 1.0, lastScanDate: scanDate,
            householdSize: 2, usageHistory: usage
        )
        let linearC = linear.confidence(
            lastScanConfidence: 1.0, lastScanDate: scanDate,
            householdSize: 2, usageHistory: usage
        )
        XCTAssertEqual(learnedC, linearC, accuracy: 0.0001)
    }

    func testLearnedFitsShorterHalfLifeFromCloseEvents() {
        let learned = LearnedDecayModel(category: .dryGoods)
        let defaultLinear = LinearDecayModel(category: .dryGoods)
        // 6 events one day apart → empirical half-life ~1 day
        let usage = (0..<6).map { i in
            ItemQuantityLog(
                recordedAt: .daysAgo(Double(200 - i)),
                measureType: .count,
                measureValue: 0.05,
                measureUnit: .unit,
                measureConfidence: 1.0,
                source: .manual
            )
        }
        let scanDate = Date.daysAgo(10)
        let learnedC = learned.confidence(
            lastScanConfidence: 1.0, lastScanDate: scanDate,
            householdSize: 1, usageHistory: usage
        )
        let defaultC = defaultLinear.confidence(
            lastScanConfidence: 1.0, lastScanDate: scanDate,
            householdSize: 1, usageHistory: usage
        )
        XCTAssertLessThan(learnedC, defaultC,
            "Learned model should decay faster once it has fit a short half-life")
    }
}
