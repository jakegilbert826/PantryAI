import Foundation

enum PantryError: LocalizedError, Equatable {
    case network(String)
    case decoding(String)
    case backendOffline
    case camera(String)
    case missingAPIKey
    case keychain(String)
    case geminiRefused(String)

    var errorDescription: String? {
        switch self {
        case .network(let m):      return "Network problem — \(m)"
        case .decoding(let m):     return "We couldn't read the response: \(m)"
        case .backendOffline:      return "Can't reach your local server. Inventory is read-only until it's back."
        case .camera(let m):       return "Camera unavailable — \(m)"
        case .missingAPIKey:       return "Set a Gemini API key in Settings before scanning."
        case .keychain(let m):     return "Keychain access failed: \(m)"
        case .geminiRefused(let m):return "Gemini declined to answer: \(m)"
        }
    }
}
