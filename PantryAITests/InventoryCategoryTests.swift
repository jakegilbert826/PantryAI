import XCTest
@testable import PantryAI

final class InventoryCategoryTests: XCTestCase {

    func testAllNineCategoriesExist() {
        XCTAssertEqual(InventoryCategory.allCases.count, 9)
    }

    func testRawValuesMatchBackendContract() {
        // These strings are the wire contract shared with the FastAPI backend
        // and the Gemini prompt — they must not drift.
        XCTAssertEqual(InventoryCategory.freshProduce.rawValue, "fresh_produce")
        XCTAssertEqual(InventoryCategory.frozenGoods.rawValue, "frozen_goods")
        XCTAssertEqual(InventoryCategory.dryGoods.rawValue, "dry_goods")
    }

    func testStorageLocationMapping() {
        XCTAssertEqual(InventoryCategory.freshProduce.location, .fridge)
        XCTAssertEqual(InventoryCategory.dairy.location, .fridge)
        XCTAssertEqual(InventoryCategory.frozenGoods.location, .freezer)
        XCTAssertEqual(InventoryCategory.dryGoods.location, .pantry)
        XCTAssertEqual(InventoryCategory.snacks.location, .pantry)
    }

    func testEveryCategoryHasNonEmptyDisplayName() {
        for category in InventoryCategory.allCases {
            XCTAssertFalse(category.displayName.isEmpty)
        }
    }

    func testCategoryIDEqualsRawValue() {
        for category in InventoryCategory.allCases {
            XCTAssertEqual(category.id, category.rawValue)
        }
    }

    func testUnknownRawValueFailsToInitialise() {
        XCTAssertNil(InventoryCategory(rawValue: "spaceship"))
    }

    func testStorageLocationDisplayNameIsCapitalised() {
        XCTAssertEqual(StorageLocation.fridge.displayName, "Fridge")
        XCTAssertEqual(StorageLocation.freezer.displayName, "Freezer")
        XCTAssertEqual(StorageLocation.pantry.displayName, "Pantry")
    }
}
