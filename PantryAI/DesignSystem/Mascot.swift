import SwiftUI

/// The avocado-pit-style mascot from the welcome screen.
struct Mascot: View {
    var size: CGFloat = 170
    var fill: Color = Theme.amber
    var ink: Color = Theme.ink

    var body: some View {
        ZStack {
            // Body
            BodyShape()
                .fill(fill)
            BodyShape()
                .stroke(ink, lineWidth: 3.5)

            // Leaf tuft (two halves)
            LeafLeft()
                .fill(Theme.mint)
                .overlay(LeafLeft().stroke(ink, lineWidth: 3))
            LeafRight()
                .fill(Theme.mint)
                .overlay(LeafRight().stroke(ink, lineWidth: 3))

            // Eyes
            Path { p in
                p.move(to: .init(x: 75, y: 100))
                p.addQuadCurve(to: .init(x: 85, y: 100), control: .init(x: 80, y: 90))
            }
            .stroke(ink, style: .init(lineWidth: 3.5, lineCap: .round))
            Path { p in
                p.move(to: .init(x: 115, y: 100))
                p.addQuadCurve(to: .init(x: 125, y: 100), control: .init(x: 120, y: 90))
            }
            .stroke(ink, style: .init(lineWidth: 3.5, lineCap: .round))

            // Cheeks
            Circle().fill(Theme.rose.opacity(0.7))
                .frame(width: 10, height: 10).position(x: 68, y: 118)
            Circle().fill(Theme.rose.opacity(0.7))
                .frame(width: 10, height: 10).position(x: 132, y: 118)

            // Smile
            Path { p in
                p.move(to: .init(x: 88, y: 122))
                p.addQuadCurve(to: .init(x: 112, y: 122), control: .init(x: 100, y: 134))
            }
            .stroke(ink, style: .init(lineWidth: 3.5, lineCap: .round))
        }
        .frame(width: 200, height: 200)
        .scaleEffect(size / 200)
        .frame(width: size, height: size)
    }

    private struct BodyShape: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: .init(x: 40, y: 100))
            p.addCurve(to: .init(x: 160, y: 100),
                       control1: .init(x: 40, y: 67),
                       control2: .init(x: 67, y: 40))
            p.addLine(to: .init(x: 160, y: 145))
            p.addCurve(to: .init(x: 145, y: 160),
                       control1: .init(x: 160, y: 153),
                       control2: .init(x: 153, y: 160))
            p.addLine(to: .init(x: 55, y: 160))
            p.addCurve(to: .init(x: 40, y: 145),
                       control1: .init(x: 47, y: 160),
                       control2: .init(x: 40, y: 153))
            p.closeSubpath()
            return p
        }
    }

    private struct LeafLeft: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: .init(x: 100, y: 40))
            p.addCurve(to: .init(x: 108, y: 18),
                       control1: .init(x: 97, y: 32),
                       control2: .init(x: 100, y: 22))
            p.addCurve(to: .init(x: 106, y: 40),
                       control1: .init(x: 106, y: 26),
                       control2: .init(x: 106, y: 34))
            p.closeSubpath()
            return p
        }
    }

    private struct LeafRight: Shape {
        func path(in rect: CGRect) -> Path {
            var p = Path()
            p.move(to: .init(x: 100, y: 40))
            p.addCurve(to: .init(x: 92, y: 18),
                       control1: .init(x: 103, y: 32),
                       control2: .init(x: 100, y: 22))
            p.addCurve(to: .init(x: 94, y: 40),
                       control1: .init(x: 94, y: 26),
                       control2: .init(x: 94, y: 34))
            p.closeSubpath()
            return p
        }
    }
}
