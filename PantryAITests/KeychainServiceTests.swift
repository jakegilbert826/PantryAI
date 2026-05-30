import XCTest
@testable import PantryAI

final class KeychainServiceTests: XCTestCase {

    private let keychain = KeychainService()

    override func setUp() {
        super.setUp()
        keychain.delete(.geminiAPIKey)
    }

    override func tearDown() {
        keychain.delete(.geminiAPIKey)
        super.tearDown()
    }

    func testSetThenGetReturnsValue() throws {
        try keychain.set("abc123", for: .geminiAPIKey)
        XCTAssertEqual(keychain.get(.geminiAPIKey), "abc123")
    }

    func testGetReturnsNilWhenAbsent() {
        XCTAssertNil(keychain.get(.geminiAPIKey))
    }

    func testSetOverwritesExistingValue() throws {
        try keychain.set("first", for: .geminiAPIKey)
        try keychain.set("second", for: .geminiAPIKey)
        XCTAssertEqual(keychain.get(.geminiAPIKey), "second")
    }

    func testDeleteRemovesValue() throws {
        try keychain.set("temp", for: .geminiAPIKey)
        keychain.delete(.geminiAPIKey)
        XCTAssertNil(keychain.get(.geminiAPIKey))
    }

    func testDeletingAbsentKeyDoesNotCrash() {
        XCTAssertNoThrow(keychain.delete(.geminiAPIKey))
    }
}
