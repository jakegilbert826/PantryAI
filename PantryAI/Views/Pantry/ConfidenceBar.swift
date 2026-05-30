import SwiftUI

/// Horizontal "fullness" bar used in detail rows. Green > 0.6, amber 0.25–0.6,
/// red < 0.25 — same thresholds the handoff calls out.
struct ConfidenceBar: View {
    let percentage: Double
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.border)
                Capsule()
                    .fill(color)
                    .frame(width: max(0, geo.size.width * percentage.clamped))
            }
        }
        .frame(height: height)
    }

    private var color: Color {
        if percentage > 0.6 { return Theme.fresh }
        if percentage > 0.25 { return Theme.amber }
        return Theme.alert
    }
}

private extension Double {
    var clamped: Double { Swift.max(0, Swift.min(1, self)) }
}
