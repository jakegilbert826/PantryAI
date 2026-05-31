import SwiftUI

struct RecipeCard: View {
    let recipe: RecipeSuggestion
    var isSaved: Bool = false
    var onSave: () -> Void = {}

    var body: some View {
        ChunkyCard(background: Theme.surface, radius: Theme.cardRadius) {
            VStack(alignment: .leading, spacing: 12) {
                // Image placeholder — striped, since prototype only has placeholder art
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(coverColor)
                    StripesView()
                        .opacity(0.4)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    CaptionText(text: "IMG · \(recipe.name)", color: Theme.ink2)
                        .padding(12)
                }
                .frame(height: 110)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                )

                DisplayText(text: recipe.name, size: 22, italic: true)
                HStack(spacing: 10) {
                    Label("\(Int(recipe.coveragePercent))% cover", systemImage: "checkmark.circle")
                    if !recipe.missingIngredients.isEmpty {
                        Label("\(recipe.missingIngredients.count) missing", systemImage: "cart")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.ink2)

                fromYourPantry

                HStack(spacing: 8) {
                    NavigationLink {
                        LiveCookingView(recipe: recipe)
                    } label: {
                        Text("Start cooking")
                            .font(.displayFallback(13))
                            .tracking(0.2)
                            .padding(.vertical, 8)
                            .padding(.horizontal, 14)
                            .frame(maxWidth: .infinity)
                            .foregroundStyle(Theme.bg)
                            .background(Capsule(style: .continuous).fill(Theme.ink))
                    }
                    .buttonStyle(.plain)

                    CircleIconButton(
                        systemName: isSaved ? "heart.fill" : "heart",
                        background: isSaved ? Theme.rose : Theme.bg,
                        foreground: isSaved ? Theme.ink : Theme.ink
                    ) { onSave() }
                }
            }
            .padding(14)
        }
    }

    private var fromYourPantry: some View {
        VStack(alignment: .leading, spacing: 6) {
            CaptionText(text: "FROM YOUR PANTRY", color: Theme.ink2)
            ForEach(recipe.requiredIngredients.prefix(4), id: \.self) { ing in
                HStack {
                    Text(ing).font(.system(size: 12))
                    Spacer()
                    Text(recipe.missingIngredients.contains(ing) ? "missing" : "have")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ink2)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.bg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(style: .init(lineWidth: 1, dash: [3, 3]))
                .foregroundStyle(Theme.border)
        )
    }

    private var coverColor: Color {
        let palette = [Theme.mint, Theme.sky, Theme.rose, Theme.amber, Theme.lilac]
        let idx = abs(recipe.name.hashValue) % palette.count
        return palette[idx]
    }
}

/// Diagonal stripe overlay — mirrors the `.stripes` CSS class in the prototype.
struct StripesView: View {
    var body: some View {
        GeometryReader { geo in
            let size = max(geo.size.width, geo.size.height)
            Canvas { ctx, _ in
                let step: CGFloat = 12
                var i: CGFloat = -size
                while i < size * 2 {
                    var p = Path()
                    p.move(to: .init(x: i, y: -size))
                    p.addLine(to: .init(x: i + size * 2, y: size * 2))
                    ctx.stroke(p, with: .color(Theme.ink.opacity(0.06)), lineWidth: 6)
                    i += step
                }
            }
        }
    }
}
