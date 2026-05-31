import SwiftUI

struct LiveCookingView: View {
    var recipe: RecipeSuggestion? = nil
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)

            Spacer()

            VStack(spacing: 20) {
                ZStack {
                    Circle().fill(Theme.amber)
                    Circle().stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                    Image(systemName: "timer")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(Theme.ink)
                }
                .frame(width: 100, height: 100)

                VStack(spacing: 8) {
                    Text("Coming Soon")
                        .font(.displayFallback(28, italic: true))
                        .foregroundStyle(Theme.ink)
                    Text("Live cooking mode is on the way — step-by-step instructions and a built-in timer, right when you need them.")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.ink2)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 40)

            Spacer()
            Spacer()
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemName: "chevron.left") { dismiss() }
            VStack(alignment: .center, spacing: 2) {
                CaptionText(text: "LIVE COOKING")
                if let name = recipe?.name {
                    DisplayText(text: name, size: 16, italic: true)
                } else {
                    Text("Step-by-step mode")
                        .font(.displayFallback(15))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(maxWidth: .infinity)
            CircleIconButton(systemName: "timer", background: Theme.amber) {}
        }
        .padding(.top, 70)
    }
}
