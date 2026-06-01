import SwiftUI

struct RecipeChatView: View {
    let vm: RecipesViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var messageText = ""
    @State private var messages: [ChatMessage] = []
    @State private var isStreaming = false
    @FocusState private var inputFocused: Bool
    @State private var sessions: [ChatSession] = []
    @State private var currentSessionId = UUID()
    @State private var showingRecents = false

    private let sessionsKey = "chat.sessions"

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
        .onAppear { loadSessions() }
        .onDisappear { saveCurrentSession() }
        .sheet(isPresented: $showingRecents) {
            RecentsSheet(sessions: sessions) { session in
                restoreSession(session)
                showingRecents = false
            } onDelete: { session in
                deleteSession(session)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
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
            HStack(spacing: 8) {
                RecentsPillButton { showingRecents = true }
                CircleIconButton(systemName: "plus", background: Theme.amber) {
                    startNewChat()
                }
            }
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
                RecipeMarkdownView(markdown: msg.markdownText)
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

        let history = messages.map { ChatTurn(role: $0.role == .user ? .user : .model, text: $0.text) }

        messages.append(ChatMessage(role: .pip, text: ""))
        isStreaming = true

        Task {
            do {
                let stream = try await vm.streamChatRecipe(history: history)
                for try await chunk in stream {
                    messages[messages.count - 1].text += chunk
                }
                let fullText = messages[messages.count - 1].text
                await vm.applyInventoryActions(from: fullText)
                messages[messages.count - 1].text = fullText.markdownOnly
            } catch {
                messages[messages.count - 1].text = "Oops — something went wrong. Please try again."
            }
            isStreaming = false
            saveCurrentSession()
        }
    }

    // MARK: Session management

    private func loadSessions() {
        guard let data = UserDefaults.standard.data(forKey: sessionsKey),
              let decoded = try? JSONDecoder().decode([ChatSession].self, from: data)
        else { return }
        sessions = decoded
        if let latest = sessions.first {
            messages = latest.messages
            currentSessionId = latest.id
        }
    }

    private func saveCurrentSession() {
        guard !messages.isEmpty else { return }
        let userMessages = messages.filter { $0.role == .user }
        let title = userMessages.first?.text ?? "Chat"
        let session = ChatSession(
            id: currentSessionId,
            createdAt: sessions.first(where: { $0.id == currentSessionId })?.createdAt ?? .now,
            title: String(title.prefix(60)),
            messages: messages
        )
        if let idx = sessions.firstIndex(where: { $0.id == currentSessionId }) {
            sessions[idx] = session
        } else {
            sessions.insert(session, at: 0)
        }
        // Keep at most 30 sessions
        if sessions.count > 30 { sessions = Array(sessions.prefix(30)) }
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }

    private func startNewChat() {
        saveCurrentSession()
        messages = []
        currentSessionId = UUID()
        messageText = ""
    }

    private func restoreSession(_ session: ChatSession) {
        saveCurrentSession()
        messages = session.messages
        currentSessionId = session.id
    }

    private func deleteSession(_ session: ChatSession) {
        sessions.removeAll { $0.id == session.id }
        if let data = try? JSONEncoder().encode(sessions) {
            UserDefaults.standard.set(data, forKey: sessionsKey)
        }
    }
}

// MARK: - Recents pill button

private struct RecentsPillButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("Recents")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Theme.bg))
                .overlay(Capsule().stroke(Theme.ink, lineWidth: Theme.strokeWidth))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Recents sheet

private struct RecentsSheet: View {
    let sessions: [ChatSession]
    let onSelect: (ChatSession) -> Void
    let onDelete: (ChatSession) -> Void
    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recent Chats")
                    .font(.displayFallback(18))
                    .foregroundStyle(Theme.ink)
                Spacer()
                CircleIconButton(systemName: "xmark") { dismiss() }
            }
            .padding(.horizontal, 22)
            .padding(.top, 24)
            .padding(.bottom, 16)

            if sessions.isEmpty {
                Spacer()
                Text("No previous chats")
                    .font(.system(size: 15))
                    .foregroundStyle(Theme.ink2)
                Spacer()
            } else {
                ScrollView {
                    VStack(spacing: 10) {
                        ForEach(sessions) { session in
                            Button {
                                onSelect(session)
                            } label: {
                                HStack(spacing: 12) {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(session.title)
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Theme.ink)
                                            .lineLimit(2)
                                            .multilineTextAlignment(.leading)
                                        Text(dateFormatter.string(from: session.createdAt))
                                            .font(.system(size: 12))
                                            .foregroundStyle(Theme.ink2)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(Theme.ink2)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .fill(Theme.surface)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                                .stroke(Theme.ink, lineWidth: Theme.strokeWidth)
                                        )
                                )
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    onDelete(session)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(Theme.bg)
    }
}

// MARK: - Supporting types

private struct ChatMessage: Identifiable, Codable {
    let id: UUID
    let role: Role
    var text: String
    enum Role: String, Codable { case user, pip }

    init(id: UUID = UUID(), role: Role, text: String) {
        self.id = id
        self.role = role
        self.text = text
    }

    var markdownText: String { text.markdownOnly }
}

private struct ChatSession: Identifiable, Codable {
    let id: UUID
    let createdAt: Date
    let title: String
    var messages: [ChatMessage]
}

private extension String {
    var markdownOnly: String {
        guard let range = self.range(of: "---JSON---") else { return self }
        return String(self[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
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
