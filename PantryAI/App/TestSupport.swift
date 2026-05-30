import Foundation

/// Launch-argument hooks used by the UI test bundle to put the app into a
/// known state before the first frame renders. No-op during normal use — the
/// guard means none of this runs unless `-uitests` is passed on launch.
///
/// Supported arguments (combine freely):
///   -uitests           required gate; nothing below runs without it
///   -resetOnboarding   force the onboarding flow to show
///   -skipOnboarding    jump straight to the main tab view
///   -resetDefaults     clear the AppConfig-backed UserDefaults keys
enum TestSupport {
    static func applyLaunchArgumentsIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        guard args.contains("-uitests") else { return }

        let defaults = UserDefaults.standard

        if args.contains("-resetDefaults") {
            for key in [
                AppConfig.Keys.baseURL,
                AppConfig.Keys.geminiModel,
                AppConfig.Keys.callGeminiDirectly,
                AppConfig.Keys.showDecayModelDebug,
                AppConfig.Keys.householdSize,
            ] {
                defaults.removeObject(forKey: key)
            }
        }

        // Onboarding flags are last so they win over -resetDefaults.
        if args.contains("-resetOnboarding") {
            defaults.set(false, forKey: AppConfig.Keys.hasOnboarded)
        }
        if args.contains("-skipOnboarding") {
            defaults.set(true, forKey: AppConfig.Keys.hasOnboarded)
        }
    }
}
