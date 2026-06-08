import XCTest
import SwiftData
@testable import PantryAI

@MainActor
final class SettingsViewModelTests: XCTestCase {

    private var context: ModelContext!

    override func setUp() {
        super.setUp()
        context = TestModelContainer.make()
        clearDefaults()
    }

    override func tearDown() {
        clearDefaults()
        KeychainService().delete(.geminiAPIKey)
        super.tearDown()
    }

    private func clearDefaults() {
        let d = UserDefaults.standard
        for key in [
            AppConfig.Keys.baseURL,
            AppConfig.Keys.geminiModel,
            AppConfig.Keys.showDecayModelDebug,
            AppConfig.Keys.householdSize,
        ] {
            d.removeObject(forKey: key)
        }
    }

    func testHouseholdSizeChangePersistsToPreferences() {
        let vm = SettingsViewModel(context: context)
        vm.householdSize = 4
        XCTAssertEqual(UserPreferences.shared.householdSize, 4)
    }

    func testBaseURLChangePersistsToDefaults() {
        let vm = SettingsViewModel(context: context)
        vm.baseURLString = "http://192.168.1.50:8000"
        XCTAssertEqual(
            UserDefaults.standard.string(forKey: AppConfig.Keys.baseURL),
            "http://192.168.1.50:8000"
        )
    }

    func testGeminiModelChangePersistsToDefaults() {
        let vm = SettingsViewModel(context: context)
        vm.geminiModel = "gemini-2.0-pro"
        XCTAssertEqual(AppConfig.geminiModel, "gemini-2.0-pro")
    }

    func testDebugTogglePersistsToDefaults() {
        let vm = SettingsViewModel(context: context)
        vm.showDebugModelIDs = true
        XCTAssertTrue(AppConfig.showDecayModelDebug)
    }

    func testPersistAPIKeyStoresThenClears() {
        let vm = SettingsViewModel(context: context)
        vm.geminiAPIKey = "secret-123"
        vm.persistAPIKey()
        XCTAssertEqual(KeychainService().get(.geminiAPIKey), "secret-123")

        // Emptying the field should remove the key from the Keychain.
        vm.geminiAPIKey = ""
        vm.persistAPIKey()
        XCTAssertNil(KeychainService().get(.geminiAPIKey))
    }

    func testClearAllInventoryEmptiesStore() throws {
        let service = InventoryService(context: context)
        try service.upsert([
            InventoryItem(name: "Rice", foodCategory: .dryGoods),
        ])
        let vm = SettingsViewModel(context: context)
        vm.clearAllInventory()
        XCTAssertTrue(try service.all().isEmpty)
    }
}
