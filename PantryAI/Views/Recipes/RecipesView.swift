import SwiftUI
import SwiftData

struct RecipesView: View {
    @Environment(\.modelContext) private var context
    @State private var vm: RecipesViewModel?
    @State private var selected: RecipeSuggestion?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                contextPill
                if let vm {
                    if vm.isLoading && vm.suggestions.isEmpty {
                        loadingPlaceholder
                    } else if vm.suggestions.isEmpty {
                        emptyState(vm)
                    } else {
                        list(vm)
                    }
                }
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 22)
        }
        .background(Theme.bg)
        .onAppear {
            if vm == nil {
                vm = RecipesViewModel(context: context)
                Task { await vm?.refresh() }
            }
        }
        .sheet(item: $selected) { recipe in
            if let vm {
                RecipeDetailView(recipe: recipe, vm: vm)
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemName: "chevron.left") {}
            VStack(alignment: .center, spacing: 2) {
                CaptionText(text: "RECIPE CHAT")
                HStack(spacing: 6) {
                    Circle().fill(Theme.fresh).frame(width: 8, height: 8)
                    Text("Pip is cooking")
                        .font(.displayFallback(15))
                }
            }
            .frame(maxWidth: .infinity)
            CircleIconButton(systemName: "ellipsis", background: Theme.amber) {}
        }
        .padding(.top, 70)
    }

    private var contextPill: some View {
        HStack(spacing: 10) {
            Image(systemName: "leaf").foregroundStyle(Theme.ink)
            Text("Using ")
                .font(.system(size: 12))
                .foregroundStyle(Theme.ink2)
            + Text("low-confidence items").font(.system(size: 12, weight: .bold)).foregroundColor(Theme.ink)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: Theme.strokeWidth, dash: [4, 4]))
                .foregroundStyle(Theme.ink)
        )
    }

    @ViewBuilder
    private func list(_ vm: RecipesViewModel) -> some View {
        VStack(spacing: 12) {
            ForEach(vm.suggestions) { recipe in
                RecipeCard(recipe: recipe)
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

    private func emptyState(_ vm: RecipesViewModel) -> some View {
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
