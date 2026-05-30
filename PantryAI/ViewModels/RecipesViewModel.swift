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

    init(context: ModelContext, gemini: GeminiServiceProtocol = GeminiService()) {
        self.context = context
        self.gemini = gemini
        self.inventory = InventoryService(context: context)
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
            suggestionsCacheKey = fingerprint
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
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
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
