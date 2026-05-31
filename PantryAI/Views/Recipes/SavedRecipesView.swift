import SwiftUI

struct SavedRecipesView: View {
    let vm: RecipesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: RecipeSuggestion?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if vm.savedRecipes.isEmpty {
                    emptyState
                } else {
                    savedList
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 22)
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
        .sheet(item: $selected) { recipe in
            RecipeDetailView(recipe: recipe, vm: vm)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemName: "chevron.left") { dismiss() }
            VStack(alignment: .center, spacing: 2) {
                CaptionText(text: "SAVED RECIPES")
                Text("Your collection")
                    .font(.displayFallback(15))
                    .foregroundStyle(Theme.ink)
            }
            .frame(maxWidth: .infinity)
            CircleIconButton(systemName: "heart.fill", background: Theme.rose) {}
        }
        .padding(.top, 70)
    }

    @ViewBuilder
    private var savedList: some View {
        VStack(spacing: 12) {
            ForEach(vm.savedRecipes) { recipe in
                RecipeCard(recipe: recipe, isSaved: true, onSave: { vm.toggleSave(recipe) })
                    .onTapGesture { selected = recipe }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Mascot(size: 120)
            Text("No saved recipes yet.")
                .font(.displayFallback(18, italic: true))
                .foregroundStyle(Theme.ink)
            Text("Tap the heart on any recipe to save it here.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
