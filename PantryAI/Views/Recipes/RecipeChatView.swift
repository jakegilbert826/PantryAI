import SwiftUI

struct RecipeChatView: View {
    let vm: RecipesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isStreaming = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 22)

            if messages.isEmpty {
                Spacer()
                placeholder
                    .padding(.horizontal, 22)
                Spacer()
            } else {
                messageList
            }

            inputBar
                .padding(.horizontal, 22)
                .padding(.bottom, 100)
        }
        .background(Theme.bg)
        .navigationBarHidden(true)
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 12) {
            CircleIconButton(systemName: "chevron.left") { dismiss() }
            VStack(alignment: .center, spacing: 2) {
                CaptionText(text: "RECIPE CHAT")
                HStack(spacing: 6) {
                    Circle().fill(isStreaming ? Theme.amber : Theme.fresh).frame(width: 8, height: 8)
                    Text(isStreaming ? "Pip is cooking…" : "Pip is ready")
                        .font(.displayFallback(15))
                        .foregroundStyle(Theme.ink)
                }
            }
            .frame(maxWidth: .infinity)
            CircleIconButton(systemName: "ellipsis", background: Theme.amber) {}
        }
        .padding(.top, 16)
    }

    // MARK: Placeholder

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
    }

    // MARK: Message list

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(messages) { msg in
                        if msg.role == .user {
                            userBubble(msg.text)
                                .id(msg.id)
                        } else {
                            pipBubble(msg)
                                .id(msg.id)
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 12)
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
            .onChange(of: messages.last?.text) { _, _ in
                proxy.scrollTo(messages.last?.id, anchor: .bottom)
            }
        }
    }

    private func userBubble(_ text: String) -> some View {
        HStack {
            Spacer(minLength: 60)
            Text(text)
                .font(.system(size: 15))
                .foregroundStyle(Theme.bg)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Theme.ink)
                )
        }
    }

    @ViewBuilder
    private func pipBubble(_ msg: ChatMessage) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ZStack {
                Circle().fill(Theme.amber)
                Circle().stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                Text("P")
                    .font(.displayFallback(14, italic: true))
                    .foregroundStyle(Theme.ink)
            }
            .frame(width: 32, height: 32)

            if msg.text.isEmpty {
                TypingIndicator()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                            )
                    )
            } else {
                RecipeMarkdownView(markdown: msg.text)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Theme.surface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                            )
                    )
            }

            Spacer(minLength: 0)
        }
    }

    // MARK: Input bar

    private var sendDisabled: Bool {
        messageText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreaming
    }

    private var inputBar: some View {
        HStack(spacing: 10) {
            TextField("What are you craving?", text: $messageText, axis: .vertical)
                .font(.system(size: 15))
                .lineLimit(4)
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
                .focused($inputFocused)
                .onSubmit { send() }

            CircleIconButton(
                systemName: "arrow.up",
                background: sendDisabled ? Theme.border : Theme.ink,
                foreground: Theme.bg
            ) {
                send()
            }
            .disabled(sendDisabled)
        }
    }

    // MARK: Send

    private func send() {
        let prompt = messageText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty, !isStreaming else { return }
        messageText = ""
        inputFocused = false
        messages.append(ChatMessage(role: .user, text: prompt))
        messages.append(ChatMessage(role: .pip, text: ""))
        isStreaming = true

        Task {
            do {
                let stream = try await vm.streamChatRecipe(userPrompt: prompt)
                for try await chunk in stream {
                    messages[messages.count - 1].text += chunk
                }
            } catch {
                messages[messages.count - 1].text = "Oops — something went wrong. Please try again."
            }
            isStreaming = false
        }
    }
}

// MARK: - Supporting types

private struct ChatMessage: Identifiable {
    let id = UUID()
    let role: Role
    var text: String
    enum Role { case user, pip }
}

private struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Theme.ink3)
                    .frame(width: 7, height: 7)
                    .scaleEffect(animating ? 1.0 : 0.5)
                    .animation(
                        .easeInOut(duration: 0.5).repeatForever().delay(Double(i) * 0.15),
                        value: animating
                    )
            }
        }
        .padding(.vertical, 3)
        .onAppear { animating = true }
    }
}
