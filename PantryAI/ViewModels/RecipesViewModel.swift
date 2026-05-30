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

    init(context: ModelContext, gemini: GeminiServiceProtocol = GeminiService()) {
        self.context = context
        self.gemini = gemini
        self.inventory = InventoryService(context: context)
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let inv = try inventory.all()
            let basis = preferExpiringSoon
                ? inv.sorted(by: { $0.currentConfidence < $1.currentConfidence })
                : inv
            let prefs = try loadPreferences()
            suggestions = try await gemini.generateRecipes(
                inventory: basis,
                preferences: prefs
            )
        } catch let err as PantryError {
            error = err
        } catch {
            self.error = .network(String(describing: error))
        }
    }

    func streamDetail(for recipe: RecipeSuggestion) async throws -> AsyncThrowingStream<String, Error> {
        let inv = try inventory.all()
        return try await gemini.streamRecipeDetail(recipe: recipe.name, inventory: inv)
    }

    private func loadPreferences() throws -> [RecipePreferenceSnapshot] {
        let descriptor = FetchDescriptor<RecipePreference>(
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        let records = try context.fetch(descriptor)
        return records.map { RecipePreferenceSnapshot(recipeName: $0.recipeName, liked: $0.liked) }
    }
}
