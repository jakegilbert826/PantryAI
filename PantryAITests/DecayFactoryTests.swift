import XCTest
@testable import PantryAI

final class DecayFactoryTests: XCTestCase {

    func testDefaultModelPerCategoryMatchesSpec() {
        let expected: [FoodCategory: String] = [
            .freshProduce: "exponential",
            .dairy:        "linear",
            .meat:         "step",
            .fish:         "step",
            .frozenGoods:  "linear",
            .dryGoods:     "linear",
            .condiments:   "exponential",
            .beverages:    "linear",
            .snacks:       "exponential",
        ]
        for (category, identifier) in expected {
            XCTAssertEqual(
                DecayModelFactory.model(for: category).modelIdentifier,
                identifier,
                "wrong default model for \(category)"
            )
        }
    }

    func testHalfLifeOverrideIsHonouredByLinearModel() {
        // 30-day override should produce higher confidence at day 10 than the
        // dryGoods default (180-day) would at the same point.
        // Wait — shorter half-life means *faster* decay. A 30-day life (15d half-life)
        // decays faster than 360-day life (180d half-life), so confidence is lower.
        let defaultModel = DecayModelFactory.model(for: .dryGoods)
        let overrideModel = DecayModelFactory.model(for: .dryGoods, halfLifeOverride: 15.0)
        let cDefault = defaultModel.confidence(
            lastScanConfidence: 1.0, lastScanDate: .daysAgo(10), householdSize: 1, usageHistory: []
        )
        let cOverride = overrideModel.confidence(
            lastScanConfidence: 1.0, lastScanDate: .daysAgo(10), householdSize: 1, usageHistory: []
        )
        XCTAssertLessThan(cOverride, cDefault, "shorter half-life override should decay faster")
    }

    func testAllModelIdentifiersAreUnique() {
        let ids = DecayModelFactory.allModelIdentifiers
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testHalfLifeDefaultsAreDefinedAndPositiveForEveryCategory() {
        for category in FoodCategory.allCases {
            XCTAssertGreaterThan(
                DecayDefaults.halfLifeDays(for: category), 0,
                "non-positive half-life for \(category)"
            )
        }
    }

    func testPerishablesHaveShorterHalfLifeThanPantryStaples() {
        XCTAssertLessThan(
            DecayDefaults.halfLifeDays(for: .fish),
            DecayDefaults.halfLifeDays(for: .dryGoods)
        )
        XCTAssertLessThan(
            DecayDefaults.halfLifeDays(for: .meat),
            DecayDefaults.halfLifeDays(for: .frozenGoods)
        )
    }
}
