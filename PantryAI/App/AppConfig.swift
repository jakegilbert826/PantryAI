import Foundation

/// Centralised, swappable configuration. Change the `baseURL` here when moving
/// off the local FastAPI dev server. All service-layer code reads from this type
/// rather than hardcoding values.
enum AppConfig {
    /// Backend base URL. Default points at a FastAPI server running on the dev
    /// machine. Settings UI can override this at runtime via `UserDefaults`.
    static var baseURL: URL {
        if let stored = UserDefaults.standard.string(forKey: Keys.baseURL),
           let url = URL(string: stored) {
            return url
        }
        return URL(string: "http://localhost:8000")!
    }

    /// Gemini model identifier. Swap to `gemini-2.0-pro` for higher-quality
    /// chat output. Vision routes always use a flash variant unless overridden.
    static var geminiModel: String {
        UserDefaults.standard.string(forKey: Keys.geminiModel) ?? "gemini-3.1-flash-lite"
    }

    /// Direct Gemini endpoint (used when not routing through the backend).
    static var geminiBaseURL: URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    }

    /// Whether to call Gemini directly from the device. When `false`, all
    /// model traffic flows through the FastAPI backend, which holds the key.
    static var callGeminiDirectly: Bool {
        UserDefaults.standard.object(forKey: Keys.callGeminiDirectly) as? Bool ?? true
    }

    /// Show decay-model identifier on every inventory row when on. Used for
    /// debugging during decay-model iteration.
    static var showDecayModelDebug: Bool {
        UserDefaults.standard.bool(forKey: Keys.showDecayModelDebug)
    }

    enum Keys {
        static let baseURL = "AppConfig.baseURL"
        static let geminiModel = "AppConfig.geminiModel"
        static let callGeminiDirectly = "AppConfig.callGeminiDirectly"
        static let showDecayModelDebug = "AppConfig.showDecayModelDebug"
        static let hasOnboarded = "AppConfig.hasOnboarded"
        static let householdSize = "AppConfig.householdSize"
    }
}
