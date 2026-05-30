import Foundation
import SwiftData

@MainActor
@Observable
final class SettingsViewModel {
    var householdSize: Int {
        didSet { UserPreferences.shared.householdSize = householdSize }
    }
    var baseURLString: String {
        didSet { UserDefaults.standard.set(baseURLString, forKey: AppConfig.Keys.baseURL) }
    }
    var geminiModel: String {
        didSet { UserDefaults.standard.set(geminiModel, forKey: AppConfig.Keys.geminiModel) }
    }
    var showDebugModelIDs: Bool {
        didSet { UserDefaults.standard.set(showDebugModelIDs, forKey: AppConfig.Keys.showDecayModelDebug) }
    }
    var geminiAPIKey: String

    var error: PantryError?

    private let context: ModelContext
    private let keychain = KeychainService()
    private let inventory: InventoryService

    init(context: ModelContext) {
        self.context = context
        self.inventory = InventoryService(context: context)
        self.householdSize = UserPreferences.shared.householdSize
        self.baseURLString = UserDefaults.standard.string(forKey: AppConfig.Keys.baseURL) ?? "http://localhost:8000"
        self.geminiModel = AppConfig.geminiModel
        self.showDebugModelIDs = AppConfig.showDecayModelDebug
        self.geminiAPIKey = KeychainService().get(.geminiAPIKey) ?? ""
    }

    func persistAPIKey() {
        do {
            if geminiAPIKey.isEmpty {
                keychain.delete(.geminiAPIKey)
            } else {
                try keychain.set(geminiAPIKey, for: .geminiAPIKey)
            }
        } catch let err as PantryError {
            error = err
        } catch {
            self.error = .keychain(String(describing: error))
        }
    }

    func clearAllInventory() {
        do {
            try inventory.clearAll()
        } catch {
            self.error = .decoding(String(describing: error))
        }
    }
}
