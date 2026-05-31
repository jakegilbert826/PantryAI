import SwiftUI

struct RecipesView: View {
    let vm: RecipesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var selected: RecipeSuggestion?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if vm.isLoading && vm.suggestions.isEmpty {
                    loadingPlaceholder
                } else if vm.suggestions.isEmpty {
                    emptyState
                } else {
                    list
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 22)
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
        .onAppear {
            Task { await vm.refresh() }
        }
        .sheet(item: $selected) { recipe in
            RecipeDetailView(recipe: recipe, vm: vm)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemName: "chevron.left") { dismiss() }
            VStack(alignment: .center, spacing: 2) {
                HStack(spacing: 6) {
                    Circle().fill(Theme.fresh).frame(width: 8, height: 8)
                    Text("Pip is cooking")
                        .font(.displayFallback(15))
                }
            }
            .frame(maxWidth: .infinity)
            CircleIconButton(systemName: "ellipsis", background: Theme.amber) {}
        }
        .padding(.top, 16)
    }

    @ViewBuilder
    private var list: some View {
        VStack(spacing: 12) {
            ForEach(vm.suggestions) { recipe in
                RecipeCard(recipe: recipe, isSaved: vm.isSaved(recipe), onSave: { vm.toggleSave(recipe) })
                    .onTapGesture { selected = recipe }
            }
        }
        PillButton(title: "Generate more", icon: "sparkles", variant: .amber, size: .regular) {
            Task { await vm.refresh(force: true) }
        }
        .padding(.top, 8)
    }

    private var loadingPlaceholder: some View {
        VStack(spacing: 12) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .fill(Theme.surface)
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).stroke(Theme.ink, lineWidth: Theme.strokeWidth))
                    .opacity(0.6)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Mascot(size: 120)
            Text("Add some items first, then ask Pip what to cook.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
            PillButton(title: "Try again", variant: .ghost, size: .small) {
                Task { await vm.refresh() }
            }
            .fixedSize()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}
