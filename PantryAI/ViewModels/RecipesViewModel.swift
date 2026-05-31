import Foundation
import SwiftData

@MainActor
@Observable
final class RecipesViewModel {
    var suggestions: [RecipeSuggestion] = []
    var isLoading = false
    var error: PantryError?
    var preferExpiringSoon = true

    private let context: ModelContext
    private let gemini: GeminiServiceProtocol
    private let inventory: InventoryService

    private var suggestionsCacheKey: String? = nil
    private var detailCache: [String: String] = [:]

    private enum UDKeys {
        static let suggestions = "recipes.suggestions"
        static let cacheKey = "recipes.cacheKey"
        static let detailCache = "recipes.detailCache"
    }

    init(context: ModelContext, gemini: GeminiServiceProtocol = GeminiService()) {
        self.context = context
        self.gemini = gemini
        self.inventory = InventoryService(context: context)
        loadFromDefaults()
    }

    func refresh(force: Bool = false) async {
        do {
            let inv = try inventory.all()
            let fingerprint = inventoryFingerprint(inv)
            if !force && fingerprint == suggestionsCacheKey && !suggestions.isEmpty {
                return
            }
            isLoading = true
            defer { isLoading = false }
            let basis = preferExpiringSoon
                ? inv.sorted(by: { $0.currentConfidence < $1.currentConfidence })
                : inv
            let prefs = try loadPreferences()
            suggestions = try await gemini.generateRecipes(
                inventory: basis,
                preferences: prefs
            )
            detailCache = [:]
            suggestionsCacheKey = fingerprint
            saveToDefaults()
        } catch let err as PantryError {
            isLoading = false
            error = err
        } catch {
            isLoading = false
            self.error = .network(String(describing: error))
        }
    }

    func streamDetail(for recipe: RecipeSuggestion) async throws -> AsyncThrowingStream<String, Error> {
        if let cached = detailCache[recipe.name] {
            return AsyncThrowingStream { continuation in
                continuation.yield(cached)
                continuation.finish()
            }
        }
        let inv = try inventory.all()
        let upstream = try await gemini.streamRecipeDetail(recipe: recipe.name, inventory: inv)
        let recipeName = recipe.name
        return AsyncThrowingStream { continuation in
            Task { [weak self] in
                var accumulated = ""
                do {
                    for try await chunk in upstream {
                        accumulated += chunk
                        continuation.yield(chunk)
                    }
                    self?.detailCache[recipeName] = accumulated
                    self?.saveToDefaults()
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func streamChatRecipe(userPrompt: String) async throws -> AsyncThrowingStream<String, Error> {
        let inv = try inventory.all()
        return try await gemini.streamChatRecipe(userPrompt: userPrompt, inventory: inv)
    }

    private func loadFromDefaults() {
        let ud = UserDefaults.standard
        if let data = ud.data(forKey: UDKeys.suggestions),
           let decoded = try? JSONDecoder().decode([RecipeSuggestion].self, from: data) {
            suggestions = decoded
        }
        suggestionsCacheKey = ud.string(forKey: UDKeys.cacheKey)
        if let data = ud.data(forKey: UDKeys.detailCache),
           let decoded = try? JSONDecoder().decode([String: String].self, from: data) {
            detailCache = decoded
        }
    }

    private func saveToDefaults() {
        let ud = UserDefaults.standard
        if let data = try? JSONEncoder().encode(suggestions) {
            ud.set(data, forKey: UDKeys.suggestions)
        }
        ud.set(suggestionsCacheKey, forKey: UDKeys.cacheKey)
        if let data = try? JSONEncoder().encode(detailCache) {
            ud.set(data, forKey: UDKeys.detailCache)
        }
    }

    private func inventoryFingerprint(_ items: [InventoryItem]) -> String {
        items.map(\.id.uuidString).sorted().joined(separator: ",")
    }

    private func loadPreferences() throws -> [RecipePreferenceSnapshot] {
        let descriptor = FetchDescriptor<RecipePreference>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)
        return records.map { RecipePreferenceSnapshot(recipeName: $0.recipeName, liked: $0.liked) }
    }
}
