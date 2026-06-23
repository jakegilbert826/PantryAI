import XCTest
@testable import PantryAI

/// Cascade behaviour for the canonicalization spine (ADR-002a): exact / fuzzy /
/// abbreviation / coarse-type veto / below-threshold → candidates / alias learning.
final class CanonicalizationServiceTests: XCTestCase {

    // MARK: Fixtures

    private func ref(_ canonical: String, _ display: String,
                     plural: String? = nil,
                     packaging: PackagingCategory = .fresh,
                     container: ContainerType? = nil) -> FoodReference {
        FoodReference(canonicalName: canonical, displayName: display, pluralName: plural,
                      defaultMeasureUnit: .unit, defaultStorageLocation: .pantry,
                      defaultPackagingCategory: packaging, defaultContainerType: container)
    }

    private func makeService(aliases: [AliasEntry] = []) -> CanonicalizationService {
        let refs = [
            ref("banana", "Banana", plural: "bananas"),
            ref("whole milk", "Whole Milk"),
            ref("cheddar cheese", "Cheddar Cheese"),
            ref("baked beans", "Baked Beans", packaging: .canned, container: .can),
            ref("tomato", "Tomato", plural: "tomatoes"),
        ]
        return CanonicalizationService(index: CanonicalIndex(references: refs, aliases: aliases))
    }

    // MARK: Lexical exact

    func testLexicalExactResolvesWithoutConfirmation() {
        let r = makeService().resolve(.init(source: .pantryScan, rawText: "Whole Milk"))
        XCTAssertEqual(r.canonicalName, "whole milk")
        XCTAssertEqual(r.matchedVia, .lexical)
        XCTAssertFalse(r.requiresConfirmation)
    }

    func testPluralResolvesToSingularCanonical() {
        let r = makeService().resolve(.init(source: .chat, rawText: "bananas"))
        XCTAssertEqual(r.canonicalName, "banana")
        XCTAssertEqual(r.matchedVia, .lexical)
    }

    func testPackSizeStrippedBeforeExactMatch() {
        // "Whole Milk 2L" → pack size stripped → exact lexical hit.
        let r = makeService().resolve(.init(source: .pantryScan, rawText: "Whole Milk 2L"))
        XCTAssertEqual(r.canonicalName, "whole milk")
    }

    // MARK: Alias

    func testAliasResolvesAndSkipsConfirmation() {
        let alias = AliasEntry(rawNormalized: "semi skimmed", canonicalName: "whole milk",
                               source: .receiptOCR, count: 5, confidence: 1.0)
        let r = makeService(aliases: [alias]).resolve(.init(source: .receiptOCR, rawText: "Semi Skimmed"))
        XCTAssertEqual(r.canonicalName, "whole milk")
        XCTAssertEqual(r.matchedVia, .alias)
        XCTAssertFalse(r.requiresConfirmation)
    }

    // MARK: Fuzzy

    func testFuzzyProposesTopCandidateButAlwaysRequiresConfirmation() {
        // Typo: "chedar chese" → fuzzy to "cheddar cheese".
        let r = makeService().resolve(.init(source: .pantryScan, rawText: "chedar chese"))
        XCTAssertEqual(r.matchedVia, .fuzzy)
        XCTAssertEqual(r.canonicalName, "cheddar cheese")
        XCTAssertTrue(r.requiresConfirmation, "fuzzy never auto-writes (ADR-002a Caveat)")
        XCTAssertFalse(r.candidates.isEmpty)
    }

    func testBelowFloorReturnsCandidatesButNoResolution() {
        // Gibberish shares no meaningful trigrams → unresolved, routed to HITL.
        let r = makeService().resolve(.init(source: .pantryScan, rawText: "zxqwv"))
        XCTAssertNil(r.canonicalName)
        XCTAssertTrue(r.requiresConfirmation)
    }

    // MARK: Receipt abbreviation expansion

    func testReceiptAbbreviationsExpandBeforeMatch() {
        // "ched chs" → "cheddar cheese" via merchant-abbrev expansion.
        let r = makeService().resolve(.init(source: .receiptOCR, ocrTokens: ["CHED", "CHS"]))
        XCTAssertEqual(r.canonicalName, "cheddar cheese")
    }

    // MARK: Coarse-type veto

    func testCoarseTypeVetoesShapeImpossibleMatch() {
        // A produce shape must not resolve to canned baked beans even on text overlap.
        let service = makeService()
        let r = service.resolve(.init(source: .pantryScan, rawText: "beans", coarseType: .produce))
        XCTAssertNotEqual(r.canonicalName, "baked beans")
    }

    func testCoarseTypeKeepsShapeConsistentMatch() {
        let r = makeService().resolve(.init(source: .pantryScan, rawText: "baked bean", coarseType: .can))
        XCTAssertEqual(r.canonicalName, "baked beans")
    }

    // MARK: Barcode stub

    func testBarcodeOnlyBundleRoutesToHITL() {
        let r = makeService().resolve(.init(source: .barcode, barcode: "5000157024671"))
        XCTAssertNil(r.canonicalName)
        XCTAssertEqual(r.matchedVia, .barcode)
        XCTAssertTrue(r.requiresConfirmation)
    }

    // MARK: Alias flywheel write-back

    func testRecordCorrectionMakesFutureResolveHitAlias() {
        let service = makeService()
        // Before: "stinky cheese" doesn't match cheddar exactly.
        let before = service.resolve(.init(source: .pantryScan, rawText: "stinky cheese"))
        XCTAssertNotEqual(before.matchedVia, .alias)

        let entry = service.recordCorrection(rawText: "stinky cheese", source: .pantryScan,
                                             canonicalName: "cheddar cheese")
        XCTAssertEqual(entry.canonicalName, "cheddar cheese")

        let after = service.resolve(.init(source: .pantryScan, rawText: "stinky cheese"))
        XCTAssertEqual(after.matchedVia, .alias)
        XCTAssertEqual(after.canonicalName, "cheddar cheese")
    }
}
