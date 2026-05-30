import SwiftUI

/// Renders a recipe written in markdown — headings, ingredient bullets, numbered
/// steps and paragraphs — using the app's chunky cream/ink theme instead of
/// dumping raw markdown syntax on screen.
///
/// It's deliberately lightweight: the recipe is streamed in token by token, so
/// `body` re-parses the whole string on every chunk. Block parsing is a simple
/// line scan that tolerates partial/incomplete markdown mid-stream, and inline
/// emphasis (`**bold**`, `*italic*`) is rendered with `AttributedString`.
struct RecipeMarkdownView: View {
    let markdown: String

    var body: some View {
        let blocks = Self.parse(markdown)
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    // MARK: - Block rendering

    @ViewBuilder
    private func view(for block: Block) -> some View {
        switch block.kind {
        case .heading(let level):
            DisplayText(text: block.text, size: level <= 1 ? 22 : 17, italic: true)
                .padding(.top, 8)

        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle()
                    .fill(Theme.fresh)
                    .frame(width: 7, height: 7)
                    .offset(y: -1)
                Text(Self.inline(block.text))
                    .font(.body(15))
                    .foregroundStyle(Theme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

        case .step(let number):
            HStack(alignment: .top, spacing: 12) {
                Text(number)
                    .font(.displayFallback(14))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Theme.amber))
                    .overlay(Circle().stroke(Theme.ink, lineWidth: Theme.strokeWidth))
                Text(Self.inline(block.text))
                    .font(.body(15))
                    .foregroundStyle(Theme.ink)
                    .lineSpacing(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }

        case .paragraph:
            Text(Self.inline(block.text))
                .font(.body(15))
                .foregroundStyle(Theme.ink2)
                .lineSpacing(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Parsing

    private struct Block {
        enum Kind {
            case heading(level: Int)
            case bullet
            case step(number: String)
            case paragraph
        }
        let kind: Kind
        let text: String
    }

    /// Splits markdown into themed blocks, one per non-empty line.
    private static func parse(_ markdown: String) -> [Block] {
        markdown
            .components(separatedBy: .newlines)
            .compactMap { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { return nil }

                if let m = line.firstMatch(of: /^(#{1,6})\s+(.+)$/) {
                    return Block(kind: .heading(level: m.1.count), text: String(m.2))
                }
                if let m = line.firstMatch(of: /^(\d+)\s*[.)]\s+(.+)$/) {
                    return Block(kind: .step(number: String(m.1)), text: String(m.2))
                }
                if let m = line.firstMatch(of: /^[-*•]\s+(.+)$/) {
                    return Block(kind: .bullet, text: String(m.1))
                }
                return Block(kind: .paragraph, text: line)
            }
    }

    /// Renders inline markdown (bold, italic, …), falling back to plain text —
    /// important during streaming when an emphasis marker may be half-typed.
    private static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }
}

#Preview {
    ScrollView {
        RecipeMarkdownView(markdown: """
        A quick, bright weeknight dinner that uses up your spinach.

        ## Ingredients
        - 200g **pasta**
        - 2 cloves garlic, sliced
        - A handful of spinach

        ## Steps
        1. Boil the pasta in well-salted water until *al dente*.
        2. Gently fry the garlic in olive oil.
        3. Toss everything together and serve.
        """)
        .padding(22)
    }
    .background(Theme.bg)
}
