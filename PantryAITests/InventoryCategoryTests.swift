import XCTest
@testable import PantryAI

final class InventoryCategoryTests: XCTestCase {

    func testAllNineCategoriesExist() {
        XCTAssertEqual(FoodCategory.allCases.count, 9)
    }

    func testRawValuesMatchBackendContract() {
        // These strings are the wire contract shared with the FastAPI backend
        // and the Gemini prompt — they must not drift.
        XCTAssertEqual(FoodCategory.freshProduce.rawValue, "fresh_produce")
        XCTAssertEqual(FoodCategory.frozenGoods.rawValue, "frozen_goods")
        XCTAssertEqual(FoodCategory.dryGoods.rawValue, "dry_goods")
    }

    func testStorageLocationMapping() {
        XCTAssertEqual(FoodCategory.freshProduce.location, .fridge)
        XCTAssertEqual(FoodCategory.dairy.location, .fridge)
        XCTAssertEqual(FoodCategory.frozenGoods.location, .freezer)
        XCTAssertEqual(FoodCategory.dryGoods.location, .pantry)
        XCTAssertEqual(FoodCategory.snacks.location, .pantry)
    }

    func testEveryCategoryHasNonEmptyDisplayName() {
        for category in FoodCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty)
        }
    }

    func testCategoryIDEqualsRawValue() {
        for category in FoodCategory.allCases {
            XCTAssertEqual(category.id, category.rawValue)
        }
    }

    func testUnknownRawValueFailsToInitialise() {
        XCTAssertNil(FoodCategory(rawValue: "spaceship"))
    }

    func testStorageLocationDisplayNameIsCapitalised() {
        XCTAssertEqual(StorageLocation.fridge.displayName, "Fridge")
        XCTAssertEqual(StorageLocation.freezer.displayName, "Freezer")
        XCTAssertEqual(StorageLocation.pantry.displayName, "Pantry")
    }
}
