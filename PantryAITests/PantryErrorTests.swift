import XCTest
@testable import PantryAI

final class PantryErrorTests: XCTestCase {

    func testEveryCaseHasNonEmptyDescription() {
        let cases: [PantryError] = [
            .network("x"), .decoding("x"), .backendOffline,
            .camera("x"), .missingAPIKey, .keychain("x"), .geminiRefused("x"),
        ]
        for error in cases {
            XCTAssertFalse(error.errorDescription?.isEmpty ?? true,
                "empty description for \(error)")
        }
    }

    func testDescriptionInterpolatesAssociatedValue() {
        XCTAssertTrue(PantryError.network("timeout").errorDescription!.contains("timeout"))
        XCTAssertTrue(PantryError.keychain("status -25300").errorDescription!.contains("-25300"))
    }

    func testEquatableMatchesOnAssociatedValues() {
        XCTAssertEqual(PantryError.network("a"), PantryError.network("a"))
        XCTAssertNotEqual(PantryError.network("a"), PantryError.network("b"))
        XCTAssertEqual(PantryError.missingAPIKey, PantryError.missingAPIKey)
        XCTAssertNotEqual(PantryError.missingAPIKey, PantryError.backendOffline)
    }
}
