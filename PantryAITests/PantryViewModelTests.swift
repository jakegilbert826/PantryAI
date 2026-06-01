import XCTest
import SwiftData
@testable import PantryAI

@MainActor
final class PantryViewModelTests: XCTestCase {

    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        context = TestModelContainer.make()
        UserPreferences.shared.householdSize = 1
    }

    private func seed(_ items: [InventoryItem]) throws {
        try InventoryService(context: context).upsert(items)
    }

    func testLoadPullsExistingItems() throws {
        try seed([
            InventoryItem(name: "Rice", foodCategory: .dryGoods, measureConfidence: 1.0),
            InventoryItem(name: "Milk", foodCategory: .dairy, measureConfidence: 1.0),
        ])
        let vm = PantryViewModel(context: context)
        XCTAssertEqual(vm.items.count, 2)
    }

    func testHasLowItemsReflectsDepletedStock() throws {
        try seed([
            InventoryItem(name: "Old Milk", foodCategory: .dairy,
                          measureConfidence: 1.0, lastScannedAt: .daysAgo(10_000)),
            InventoryItem(name: "Fresh Rice", foodCategory: .dryGoods,
                          measureConfidence: 1.0, lastScannedAt: .now),
        ])
        let vm = PantryViewModel(context: context)
        XCTAssertTrue(vm.hasLowItems)
        XCTAssertEqual(vm.lowItems.map(\.name), ["Old Milk"])
    }

    func testByLocationAlwaysReturnsThreeOrderedBuckets() throws {
        try seed([InventoryItem(name: "Rice", foodCategory: .dryGoods, measureConfidence: 1.0)])
        let vm = PantryViewModel(context: context)
        let locations = vm.byLocation.map(\.0)
        XCTAssertEqual(locations, [.fridge, .freezer, .pantry])
    }

    func testDeleteRemovesItemAndReloads() throws {
        let item = InventoryItem(name: "Eggs", foodCategory: .dairy, measureConfidence: 1.0)
        try seed([item])
        let vm = PantryViewModel(context: context)
        vm.delete(item)
        XCTAssertTrue(vm.items.isEmpty)
    }

    func testLogUsageReducesStoredConfidence() throws {
        let item = InventoryItem(name: "Juice", foodCategory: .beverages,
                                 measureConfidence: 1.0, lastScannedAt: .now)
        try seed([item])
        let vm = PantryViewModel(context: context)
        vm.logUsage(item, fraction: 0.5)

        let reloaded = vm.items.first { $0.id == item.id }
        XCTAssertEqual(reloaded?.quantityLog.count, 1)
        XCTAssertLessThan(reloaded?.currentConfidence ?? 1, 1.0)
    }
}
