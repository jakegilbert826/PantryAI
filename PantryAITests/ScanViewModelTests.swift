import XCTest
import SwiftData
import UIKit
@testable import PantryAI

@MainActor
final class ScanViewModelTests: XCTestCase {

    private var context: ModelContext!
    private var gemini: MockGeminiService!

    override func setUp() {
        super.setUp()
        context = TestModelContainer.make()
        gemini = MockGeminiService()
    }

    private func makeVM() -> ScanViewModel {
        ScanViewModel(context: context, gemini: gemini)
    }

    private func solidImage() -> UIImage {
        let size = CGSize(width: 8, height: 8)
        return UIGraphicsImageRenderer(size: size).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    func testAddPhotoStoresJPEGData() {
        let vm = makeVM()
        vm.add(photo: solidImage())
        XCTAssertEqual(vm.captured.count, 1)
        XCTAssertFalse(vm.captured[0].isEmpty)
    }

    func testCanCaptureMoreCapsAtSixPhotos() {
        let vm = makeVM()
        for _ in 0..<6 { vm.add(photo: solidImage()) }
        XCTAssertFalse(vm.canCaptureMore)
        XCTAssertEqual(vm.captured.count, 6)
    }

    func testAnalyseMovesToReviewAndMergesDuplicates() async {
        gemini.scanResult = [
            ScannedItem(name: "Eggs", category: .dairy, brand: nil,
                        quantity: 1, unit: nil, confidence: 0.6),
            ScannedItem(name: "eggs", category: .dairy, brand: nil,
                        quantity: 1, unit: nil, confidence: 0.9), // dup, higher conf
            ScannedItem(name: "Milk", category: .dairy, brand: nil,
                        quantity: 1, unit: nil, confidence: 0.8),
        ]
        let vm = makeVM()
        vm.add(photo: solidImage())
        await vm.analyse()

        XCTAssertEqual(vm.stage, .review)
        XCTAssertEqual(vm.detected.count, 2, "duplicate name should be merged")
        // Highest-confidence read of the duplicate is kept, and list is sorted.
        XCTAssertEqual(vm.detected.first?.name.lowercased(), "eggs")
        XCTAssertEqual(vm.detected.first?.confidence, 0.9)
    }

    func testInitialStageIsMethodPicker() {
        XCTAssertEqual(makeVM().stage, .method)
    }

    func testStartPhotoCaptureMovesToCapturing() {
        let vm = makeVM()
        vm.startPhotoCapture()
        XCTAssertEqual(vm.stage, .capturing)
        XCTAssertTrue(vm.captured.isEmpty)
    }

    func testAnalyseWithNoPhotosDoesNothing() async {
        let vm = makeVM()
        vm.startPhotoCapture()
        await vm.analyse()
        XCTAssertEqual(vm.stage, .capturing)
        XCTAssertEqual(gemini.scanCallCount, 0)
    }

    func testAnalyseSurfacesErrorAndReturnsToCapturing() async {
        gemini.scanError = PantryError.missingAPIKey
        let vm = makeVM()
        vm.add(photo: solidImage())
        await vm.analyse()

        XCTAssertEqual(vm.stage, .capturing)
        XCTAssertEqual(vm.error, .missingAPIKey)
    }

    func testToggleFlipsInclusion() async {
        gemini.scanResult = [
            ScannedItem(name: "Eggs", category: .dairy, brand: nil,
                        quantity: 1, unit: nil, confidence: 0.9),
        ]
        let vm = makeVM()
        vm.add(photo: solidImage())
        await vm.analyse()
        let item = vm.detected[0]
        XCTAssertTrue(item.include)
        vm.toggle(item)
        XCTAssertFalse(vm.detected[0].include)
    }

    func testCommitWritesIncludedItemsToInventory() async throws {
        gemini.scanResult = [
            ScannedItem(name: "Eggs", category: .dairy, brand: nil,
                        quantity: 1, unit: nil, confidence: 0.9),
            ScannedItem(name: "Spam", category: .meat, brand: nil,
                        quantity: 1, unit: nil, confidence: 0.5),
        ]
        let vm = makeVM()
        vm.add(photo: solidImage())
        await vm.analyse()
        // Exclude the second detection before committing.
        vm.toggle(vm.detected[1])
        vm.commit()

        XCTAssertEqual(vm.stage, .done)
        let stored = try InventoryService(context: context).all()
        XCTAssertEqual(stored.count, 1)
        XCTAssertEqual(stored.first?.name, vm.detected[0].name)
    }

    func testResetClearsState() async {
        gemini.scanResult = [
            ScannedItem(name: "Eggs", category: .dairy, brand: nil,
                        quantity: 1, unit: nil, confidence: 0.9),
        ]
        let vm = makeVM()
        vm.add(photo: solidImage())
        await vm.analyse()
        vm.reset()

        XCTAssertEqual(vm.stage, .method)
        XCTAssertTrue(vm.captured.isEmpty)
        XCTAssertTrue(vm.detected.isEmpty)
        XCTAssertNil(vm.error)
    }
}
