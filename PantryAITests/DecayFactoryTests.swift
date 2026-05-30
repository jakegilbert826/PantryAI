import XCTest
@testable import PantryAI

final class DecayFactoryTests: XCTestCase {

    func testDefaultModelPerCategoryMatchesSpec() {
        let expected: [InventoryCategory: String] = [
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

    func testModelByIdentifierResolvesEachKnownID() {
        for id in DecayModelFactory.allModelIdentifiers {
            let model = DecayModelFactory.model(byIdentifier: id, category: .dairy)
            XCTAssertNotNil(model, "factory failed to resolve \(id)")
            XCTAssertEqual(model?.modelIdentifier, id)
        }
    }

    func testModelByUnknownIdentifierReturnsNil() {
        XCTAssertNil(DecayModelFactory.model(byIdentifier: "quantum", category: .dairy))
    }

    func testAllModelIdentifiersAreUnique() {
        let ids = DecayModelFactory.allModelIdentifiers
        XCTAssertEqual(Set(ids).count, ids.count)
    }

    func testHalfLifeDefaultsAreDefinedAndPositiveForEveryCategory() {
        for category in InventoryCategory.allCases {
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
