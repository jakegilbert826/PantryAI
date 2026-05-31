import SwiftUI

struct SavedRecipesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                emptyState
                Spacer(minLength: 120)
            }
            .padding(.horizontal, 22)
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
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
            CircleIconButton(systemName: "bookmark.fill", background: Theme.sky) {}
        }
        .padding(.top, 70)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Mascot(size: 120)
            Text("No saved recipes yet.")
                .font(.displayFallback(18, italic: true))
                .foregroundStyle(Theme.ink)
            Text("Tap the bookmark on any recipe to save it here.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }
}
