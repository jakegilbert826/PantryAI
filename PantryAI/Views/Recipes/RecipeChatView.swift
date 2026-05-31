import SwiftUI

struct RecipeChatView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)
            Spacer()
            placeholder
            Spacer()
            inputBar
                .padding(.horizontal, 22)
                .padding(.bottom, 100)
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
    }

    private var header: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemName: "chevron.left") { dismiss() }
            VStack(alignment: .center, spacing: 2) {
                CaptionText(text: "RECIPE CHAT")
                HStack(spacing: 6) {
                    Circle().fill(Theme.fresh).frame(width: 8, height: 8)
                    Text("Pip is ready")
                        .font(.displayFallback(15))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(maxWidth: .infinity)
            CircleIconButton(systemName: "ellipsis", background: Theme.amber) {}
        }
        .padding(.top, 70)
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Mascot(size: 120)
            Text("Tell Pip what to make")
                .font(.displayFallback(18, italic: true))
                .foregroundStyle(Theme.ink)
            Text("Describe a craving, a cuisine, or ingredients you want to use — Pip will build the recipe.")
                .font(.system(size: 14))
                .foregroundStyle(Theme.ink2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 22)
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("What are you craving?", text: $messageText)
                .font(.system(size: 15))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .fill(Theme.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                        )
                )
            CircleIconButton(
                systemName: "arrow.up",
                background: Theme.ink,
                foreground: Theme.bg
            ) {}
        }
    }
}
