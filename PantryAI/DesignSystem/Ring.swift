import SwiftUI

/// Mirrors the React `<Ring />` component — a percentage ring used everywhere
/// confidence is shown (item cards, hero card, detail header).
struct Ring: View {
    let percentage: Double
    var size: CGFloat = 44
    var stroke: CGFloat = 5
    var color: Color = Theme.ink
    var track: Color = Theme.ink.opacity(0.15)
    var showsLabel: Bool = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(track, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: percentage.clamped(0, 1))
                .stroke(color, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if showsLabel {
                Text("\(Int(percentage.clamped(0, 1) * 100))")
                    .font(.system(size: size * 0.32, weight: .heavy, design: .rounded))
                    .foregroundStyle(color)
            }
        }
        .frame(width: size, height: size)
    }
}

private extension Double {
    func clamped(_ low: Double, _ high: Double) -> Double { Swift.max(low, Swift.min(high, self)) }
}
