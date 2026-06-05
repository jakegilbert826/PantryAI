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
            RecipePreference.self,
            ScanSession.self,
        ])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .tint(Theme.ink)
                .onAppear {
                    InventoryItem.migrateBaseUnits(in: sharedModelContainer.mainContext)
                }
        }
        .modelContainer(sharedModelContainer)
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
