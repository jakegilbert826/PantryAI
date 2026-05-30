import SwiftUI
import SwiftData

/// Tinder-style preference capture. Each card is a recipe; swipe right to
/// "like", left to "dislike". Results stored as `RecipePreference` records.
struct RecipeSwipeView: View {
    var onComplete: () -> Void
    @Environment(\.modelContext) private var context
    @State private var deck: [SeedRecipe] = SeedRecipe.all.shuffled()
    @State private var dragOffset: CGSize = .zero

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer().frame(height: 70)
            CaptionText(text: "STEP 3 OF 4")
                .padding(.horizontal, 24)
            DisplayText(text: "Swipe to teach Pip.", size: 34, italic: true)
                .padding(.horizontal, 24)
                .padding(.top, 6)
            Text("Right if you'd cook it. Left if you wouldn't. About 8 cards.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink2)
                .padding(.horizontal, 24)
                .padding(.top, 8)

            Spacer()

            ZStack {
                ForEach(deck.prefix(3).reversed()) { recipe in
                    cardView(for: recipe)
                        .offset(recipe == deck.first ? dragOffset : .zero)
                        .rotationEffect(.degrees(recipe == deck.first ? Double(dragOffset.width / 20) : 0))
                        .gesture(
                            recipe == deck.first
                            ? DragGesture()
                                .onChanged { dragOffset = $0.translation }
                                .onEnded { handleEnd($0) }
                            : nil
                        )
                        .animation(.spring(response: 0.35), value: dragOffset)
                }
            }
            .frame(height: 360)
            .padding(.horizontal, 24)

            HStack(spacing: 14) {
                Spacer()
                Button {
                    record(liked: false)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Theme.surface))
                        .overlay(Circle().stroke(Theme.ink, lineWidth: Theme.strokeWidth))
                }
                .buttonStyle(.plain)
                Button {
                    record(liked: true)
                } label: {
                    Image(systemName: "heart.fill")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(Theme.bg)
                        .frame(width: 60, height: 60)
                        .background(Circle().fill(Theme.ink))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.vertical, 18)

            PillButton(title: "Done", variant: .ghost, size: .regular, action: onComplete)
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
        }
    }

    private func cardView(for recipe: SeedRecipe) -> some View {
        ChunkyCard(background: recipe.color, radius: Theme.bigCardRadius) {
            VStack(alignment: .leading) {
                Spacer()
                CaptionText(text: recipe.cuisine.uppercased(), color: Theme.ink2)
                DisplayText(text: recipe.name, size: 34, italic: true)
                    .padding(.top, 6)
                Text(recipe.tagline)
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.ink2)
                    .padding(.top, 6)
            }
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(height: 360)
    }

    private func handleEnd(_ value: DragGesture.Value) {
        let threshold: CGFloat = 100
        if value.translation.width > threshold {
            record(liked: true)
        } else if value.translation.width < -threshold {
            record(liked: false)
        } else {
            dragOffset = .zero
        }
    }

    private func record(liked: Bool) {
        guard let top = deck.first else { onComplete(); return }
        let pref = RecipePreference(recipeName: top.name, liked: liked)
        context.insert(pref)
        try? context.save()
        deck.removeFirst()
        dragOffset = .zero
        if deck.isEmpty { onComplete() }
    }
}

private struct SeedRecipe: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let cuisine: String
    let tagline: String
    let color: Color

    static let all: [SeedRecipe] = [
        .init(name: "Cacio e pepe", cuisine: "Italian", tagline: "Pasta, pecorino, black pepper, twenty minutes.", color: Theme.amber),
        .init(name: "Green curry", cuisine: "Thai", tagline: "Coconut milk and basil over jasmine rice.", color: Theme.mint),
        .init(name: "Shakshuka", cuisine: "North African", tagline: "Eggs poached in spiced tomato. One pan.", color: Theme.rose),
        .init(name: "Bibimbap", cuisine: "Korean", tagline: "Rice bowl with whatever's in the fridge.", color: Theme.lilac),
        .init(name: "Roast chicken", cuisine: "Sunday", tagline: "Lemon, garlic, two hours, no fuss.", color: Theme.sky),
        .init(name: "Tacos al pastor", cuisine: "Mexican", tagline: "Marinated pork, pineapple, charred.", color: Theme.rose),
        .init(name: "Aglio e olio", cuisine: "Italian", tagline: "Garlic, oil, chilli, parsley. Done.", color: Theme.amber),
        .init(name: "Vegetable pho", cuisine: "Vietnamese", tagline: "Slow broth, fresh herbs, lime.", color: Theme.mint),
    ]
}
