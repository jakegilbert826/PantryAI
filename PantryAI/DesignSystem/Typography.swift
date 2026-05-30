import SwiftUI

/// Typography helpers. The design uses Funnel Display for headings (often
/// italic) and Inter for body. Funnel Display isn't a system font on iOS, so
/// when the font isn't bundled we fall back to a heavy rounded system font
/// which keeps the bold, friendly silhouette.
extension Font {
    static func display(_ size: CGFloat, italic: Bool = false) -> Font {
        let f = Font.custom("FunnelDisplay-ExtraBold", size: size)
        return italic ? f.italic() : f
    }

    static func displayFallback(_ size: CGFloat, italic: Bool = false) -> Font {
        // Used when Funnel Display isn't installed — system rounded heavy reads close.
        let base = Font.system(size: size, weight: .heavy, design: .rounded)
        return italic ? base.italic() : base
    }

    static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font.custom("Inter-Regular", size: size).weight(weight)
    }

    static var caption10: Font {
        Font.system(size: 10, weight: .semibold).monospaced()
    }
}

struct DisplayText: View {
    let text: String
    var size: CGFloat = 22
    var italic: Bool = false
    var color: Color = Theme.ink

    var body: some View {
        Text(text)
            .font(.displayFallback(size, italic: italic))
            .kerning(-0.5)
            .foregroundStyle(color)
            .lineSpacing(0)
    }
}

struct CaptionText: View {
    let text: String
    var color: Color = Theme.ink3

    var body: some View {
        Text(text.uppercased())
            .font(.caption10)
            .tracking(1.6)
            .foregroundStyle(color)
    }
}
