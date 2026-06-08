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
            InventoryItem(name: "Rice", foodCategory: .dryGoods),
            InventoryItem(name: "Milk", foodCategory: .dairy),
        ])
        let vm = PantryViewModel(context: context)
        XCTAssertEqual(vm.items.count, 2)
    }

    func testHasLowItemsReflectsDepletedStock() throws {
        try seed([
            InventoryItem(name: "Old Milk", foodCategory: .dairy,
                          lastScannedAt: .daysAgo(10_000)),
            InventoryItem(name: "Fresh Rice", foodCategory: .dryGoods,
                          lastScannedAt: .now),
        ])
        let vm = PantryViewModel(context: context)
        XCTAssertTrue(vm.hasLowItems)
        XCTAssertEqual(vm.lowItems.map(\.name), ["Old Milk"])
    }

    func testByLocationAlwaysReturnsThreeOrderedBuckets() throws {
        try seed([InventoryItem(name: "Rice", foodCategory: .dryGoods)])
        let vm = PantryViewModel(context: context)
        let locations = vm.byLocation.map(\.0)
        XCTAssertEqual(locations, [.fridge, .freezer, .pantry])
    }

    func testDeleteRemovesItemAndReloads() throws {
        let item = InventoryItem(name: "Eggs", foodCategory: .dairy)
        try seed([item])
        let vm = PantryViewModel(context: context)
        vm.delete(item)
        XCTAssertTrue(vm.items.isEmpty)
    }

    func testLogUsageAppendsUsageLog() throws {
        // v3: reads are anchor-driven, so a usage log records history without
        // mutating the decay anchors. Confidence stays full until a re-anchoring
        // observation lands.
        let item = InventoryItem(name: "Juice", foodCategory: .beverages,
                                 lastScannedAt: .now)
        try seed([item])
        let vm = PantryViewModel(context: context)
        vm.logUsage(item, fraction: 0.5)

        let reloaded = vm.items.first { $0.id == item.id }
        XCTAssertEqual(reloaded?.quantityLog.count, 1)
        XCTAssertEqual(reloaded?.quantityLog.first?.measureValue, 0.5)
    }
}
