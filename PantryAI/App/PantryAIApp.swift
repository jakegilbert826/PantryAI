import SwiftUI
import SwiftData

@main
struct PantryAIApp: App {
    @AppStorage(AppConfig.Keys.hasOnboarded) private var hasOnboarded: Bool = false

    init() {
        TestSupport.applyLaunchArgumentsIfNeeded()
        Task { await FoodReferenceService.shared.prefetch() }
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            InventoryItem.self,
            ItemQuantityLog.self,
            ConsumptionProfile.self,
            RecipePreference.self,
            ScanSession.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // v3 store-wipe migration (design §11.2): there is no production data
            // to preserve, so on an incompatible schema we delete the store and
            // recreate it fresh rather than authoring a SchemaMigrationPlan.
            PantryAIApp.wipePersistentStore()
            do {
                return try ModelContainer(for: schema, configurations: [configuration])
            } catch {
                fatalError("Could not create ModelContainer after wipe: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .tint(Theme.ink)
        }
        .modelContainer(sharedModelContainer)
    }

    /// Deletes the default on-disk SwiftData store files so the next
    /// `ModelContainer` init starts clean.
    private static func wipePersistentStore() {
        let fm = FileManager.default
        guard let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return }
        for name in ["default.store", "default.store-shm", "default.store-wal"] {
            try? fm.removeItem(at: appSupport.appendingPathComponent(name))
        }
    }
}

struct RootView: View {
    @AppStorage(AppConfig.Keys.hasOnboarded) private var hasOnboarded: Bool = false

    var body: some View {
        if hasOnboarded {
            MainTabView()
        } else {
            OnboardingView(onFinish: { hasOnboarded = true })
        }
    }
}
