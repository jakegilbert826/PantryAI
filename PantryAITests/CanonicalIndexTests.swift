import XCTest
@testable import PantryAI

/// Index construction, retrieval, alias write-back and a perf sanity check
/// (ADR-002a speed design: sub-ms per item, builds in ms).
final class CanonicalIndexTests: XCTestCase {

    private func ref(_ canonical: String, _ display: String, plural: String? = nil) -> FoodReference {
        FoodReference(canonicalName: canonical, displayName: display, pluralName: plural,
                      defaultMeasureUnit: .unit, defaultStorageLocation: .pantry,
                      defaultPackagingCategory: .fresh)
    }

    func testBuildCounts() {
        let index = CanonicalIndex(references: [ref("a", "Apple"), ref("b", "Banana")],
                                   aliases: [AliasEntry(rawNormalized: "nana", canonicalName: "b")])
        XCTAssertEqual(index.referenceCount, 2)
        XCTAssertEqual(index.aliasCount, 1)
    }

    func testLexicalKeysCoverCanonicalDisplayAndPlural() {
        let index = CanonicalIndex(references: [ref("tomato", "Tomato", plural: "tomatoes")])
        XCTAssertEqual(index.lexicalMatch("tomato"), "tomato")
        XCTAssertEqual(index.lexicalMatch("tomatoes"), "tomato")
    }

    func testTrigramFuzzyRetrievesNearMatch() {
        let index = CanonicalIndex(references: [ref("cheddar cheese", "Cheddar Cheese"),
                                                ref("banana", "Banana")])
        let hits = index.fuzzyCandidates("chedar chese")
        XCTAssertEqual(hits.first?.canonical, "cheddar cheese")
        XCTAssertGreaterThan(hits.first?.score ?? 0, 0.5)
    }

    func testUpsertAliasIsImmediatelyMatchable() {
        let index = CanonicalIndex(references: [ref("cheddar cheese", "Cheddar Cheese")])
        XCTAssertNil(index.aliasMatch("stinky"))
        index.upsertAlias(AliasEntry(rawNormalized: "stinky", canonicalName: "cheddar cheese"))
        XCTAssertEqual(index.aliasMatch("stinky")?.canonicalName, "cheddar cheese")
    }

    func testUpsertAliasBumpsCountAndKeepsStrongestConfidence() {
        let index = CanonicalIndex(references: [ref("milk", "Milk")])
        index.upsertAlias(AliasEntry(rawNormalized: "mlk", canonicalName: "milk", count: 1, confidence: 0.8))
        index.upsertAlias(AliasEntry(rawNormalized: "mlk", canonicalName: "milk", count: 1, confidence: 0.95))
        let alias = index.aliasMatch("mlk")
        XCTAssertEqual(alias?.count, 2)
        XCTAssertEqual(alias?.confidence, 0.95)
    }

    func testTrigramGenerationPadsEnds() {
        // "milk" padded → includes leading/trailing space grams.
        let grams = CanonicalIndex.trigrams(of: "milk")
        XCTAssertTrue(grams.contains(" mi"))
        XCTAssertTrue(grams.contains("lk "))
    }

    func testResolvePerfSanity() {
        // Build a few-thousand-row vocabulary and resolve a shelf-sized batch.
        let refs = (0..<3000).map { ref("food\($0)", "Food \($0)") }
        let index = CanonicalIndex(references: refs)
        let service = CanonicalizationService(index: index)
        measure {
            for i in 0..<20 {
                _ = service.resolve(.init(source: .pantryScan, rawText: "Food \(i * 7)"))
            }
        }
    }
}
