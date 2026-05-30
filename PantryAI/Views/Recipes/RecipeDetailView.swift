import SwiftUI

struct RecipeDetailView: View {
    let recipe: RecipeSuggestion
    @Bindable var vm: RecipesViewModel
    @State private var text: String = ""
    @State private var streaming = true
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if text.isEmpty {
                    typingIndicator
                } else {
                    Text(text)
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.ink)
                        .lineSpacing(4)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 40)
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
        }
        .background(Theme.bg)
        .task {
            do {
                let stream = try await vm.streamDetail(for: recipe)
                for try await chunk in stream {
                    text += chunk
                }
                streaming = false
            } catch {
                text = "Couldn't load this recipe: \(error.localizedDescription)"
                streaming = false
            }
        }
    }

    private var header: some View {
        HStack {
            CircleIconButton(systemName: "chevron.down") { dismiss() }
            Spacer()
            VStack(alignment: .center, spacing: 2) {
                CaptionText(text: "RECIPE")
                DisplayText(text: recipe.name, size: 18, italic: true)
            }
            Spacer()
            CircleIconButton(systemName: "heart", background: Theme.amber) {}
        }
    }

    private var typingIndicator: some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.ink)
                    .frame(width: 8, height: 8)
                    .opacity(0.4)
                    .scaleEffect(streaming ? 1 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.6).repeatForever().delay(Double(i) * 0.15),
                        value: streaming
                    )
            }
            Text("Pip is writing the recipe…")
                .font(.system(size: 13))
                .foregroundStyle(Theme.ink2)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.sky)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Theme.ink, lineWidth: Theme.strokeWidth)
        )
    }
}
