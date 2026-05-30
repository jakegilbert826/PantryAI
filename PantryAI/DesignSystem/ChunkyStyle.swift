import SwiftUI

/// The signature card: ink border + hard offset drop shadow (the "chunky" look).
/// Mirrors `boxShadow: '0 5px 0 var(--ink)'` from the HTML prototype.
struct ChunkyCard<Content: View>: View {
    var background: Color = Theme.surface
    var radius: CGFloat = Theme.cardRadius
    var shadowOffset: CGFloat = Theme.chunkyShadowOffset
    var stroke: Color = Theme.ink
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(stroke, lineWidth: Theme.strokeWidth)
            )
            .background(
                // Hard offset drop shadow — a translated, solid-ink rounded rect.
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(stroke)
                    .offset(y: shadowOffset)
            )
    }
}

/// Pill button — the primary call-to-action shape. Three variants match the
/// design: solid ink, ghost (outline), and amber (highlighted choice).
struct PillButton: View {
    enum Variant { case solid, ghost, amber }

    let title: String
    var icon: String? = nil
    var variant: Variant = .solid
    var size: Size = .regular
    let action: () -> Void

    enum Size {
        case small, regular, large
        var vertical: CGFloat {
            switch self {
            case .small: return 8
            case .regular: return 14
            case .large: return 18
            }
        }
        var horizontal: CGFloat {
            switch self {
            case .small: return 14
            case .regular: return 22
            case .large: return 24
            }
        }
        var font: CGFloat {
            switch self {
            case .small: return 13
            case .regular: return 15
            case .large: return 16
            }
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.displayFallback(size.font))
                    .tracking(0.2)
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: size.font - 1, weight: .bold))
                }
            }
            .padding(.vertical, size.vertical)
            .padding(.horizontal, size.horizontal)
            .frame(maxWidth: .infinity)
            .foregroundStyle(foreground)
            .background(
                Capsule(style: .continuous).fill(background)
            )
            .overlay(
                Capsule(style: .continuous).stroke(Theme.ink, lineWidth: variant == .solid ? 0 : Theme.strokeWidth)
            )
        }
        .buttonStyle(.plain)
    }

    private var background: Color {
        switch variant {
        case .solid: return Theme.ink
        case .ghost: return .clear
        case .amber: return Theme.amber
        }
    }

    private var foreground: Color {
        switch variant {
        case .solid: return Theme.bg
        case .ghost, .amber: return Theme.ink
        }
    }
}

/// Tiny circular icon button used throughout the chrome (close, back, more).
struct CircleIconButton: View {
    let systemName: String
    var background: Color = Theme.bg
    var foreground: Color = Theme.ink
    var size: CGFloat = 36
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(foreground)
                .frame(width: size, height: size)
                .background(Circle().fill(background))
                .overlay(Circle().stroke(Theme.ink, lineWidth: Theme.strokeWidth))
        }
        .buttonStyle(.plain)
    }
}
