import XCTest
import SwiftData
@testable import PantryAI

@MainActor
final class InventoryServiceTests: XCTestCase {

    private var context: ModelContext!
    private var service: InventoryService!

    override func setUp() {
        super.setUp()
        context = TestModelContainer.make()
        service = InventoryService(context: context)
    }

    override func tearDown() {
        service = nil
        context = nil
        super.tearDown()
    }

    private func makeItem(_ name: String, category: FoodCategory = .dryGoods) -> InventoryItem {
        InventoryItem(name: name, foodCategory: category, measureConfidence: 1.0)
    }

    // MARK: Insert / read

    func testUpsertInsertsNewItems() throws {
        try service.upsert([makeItem("Rice"), makeItem("Pasta")])
        let all = try service.all()
        XCTAssertEqual(all.count, 2)
        XCTAssertEqual(Set(all.map(\.name)), ["Rice", "Pasta"])
    }

    func testUpsertUpdatesExistingByCaseInsensitiveName() throws {
        try service.upsert([makeItem("Milk", category: .dairy)])
        let updated = makeItem("MILK", category: .dairy)
        updated.measureValue = 0.25
        try service.upsert([updated])

        let all = try service.all()
        XCTAssertEqual(all.count, 1, "case-folded name should dedupe")
        XCTAssertEqual(all.first?.measureValue, 0.25)
    }

    func testAllSortsByUpdatedAtDescending() throws {
        try service.upsert([makeItem("First")])
        try service.upsert([makeItem("Second")])
        let all = try service.all()
        XCTAssertEqual(all.first?.name, "Second")
    }

    // MARK: Delete (soft)

    func testDeleteRemovesItemFromAll() throws {
        let item = makeItem("Eggs", category: .dairy)
        try service.upsert([item])
        try service.delete(id: item.id)
        XCTAssertTrue(try service.all().isEmpty)
    }

    func testDeleteUnknownIDIsNoOp() throws {
        try service.upsert([makeItem("Bread")])
        try service.delete(id: UUID())
        XCTAssertEqual(try service.all().count, 1)
    }

    // MARK: Usage logging

    func testLogUsageAppendsLogToItem() throws {
        let item = makeItem("Yoghurt", category: .dairy)
        try service.upsert([item])
        try service.logUsage(itemID: item.id, quantityUsed: 0.3, source: .manual)

        let stored = try service.all().first { $0.id == item.id }
        XCTAssertEqual(stored?.quantityLog.count, 1)
        XCTAssertEqual(stored?.quantityLog.first?.measureValue, 0.3)
        XCTAssertEqual(stored?.quantityLog.first?.source, .manual)
    }

    func testLogUsageForUnknownItemIsNoOp() throws {
        XCTAssertNoThrow(try service.logUsage(itemID: UUID(), quantityUsed: 0.5))
    }

    // MARK: Grouping

    func testGroupedBucketsByStorageLocation() throws {
        try service.upsert([
            makeItem("Rice", category: .dryGoods),     // pantry
            makeItem("Milk", category: .dairy),         // fridge
            makeItem("Peas", category: .frozenGoods),   // freezer
            makeItem("Chips", category: .snacks),       // pantry
        ])
        let grouped = try service.grouped()
        XCTAssertEqual(grouped[.pantry]?.count, 2)
        XCTAssertEqual(grouped[.fridge]?.count, 1)
        XCTAssertEqual(grouped[.freezer]?.count, 1)
    }

    // MARK: Clear

    func testClearAllEmptiesTheStore() throws {
        try service.upsert([makeItem("A"), makeItem("B"), makeItem("C")])
        try service.clearAll()
        XCTAssertTrue(try service.all().isEmpty)
    }

    func testQuantityLogSurvivesReFetch() throws {
        let item = makeItem("Oats")
        try service.upsert([item])
        try service.logUsage(itemID: item.id, quantityUsed: 0.1)
        try service.logUsage(itemID: item.id, quantityUsed: 0.2)
        let stored = try service.all().first { $0.id == item.id }
        XCTAssertEqual(stored?.quantityLog.count, 2)
    }
}
