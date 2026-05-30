import SwiftUI

/// Single source of truth for the visual language.
/// Colours mirror the CSS variables in `Pantry Mobile.html`.
enum Theme {
    // MARK: Core surface
    static let canvas   = Color(hex: 0xF2B844) // amber yellow, the "outside-of-phone" canvas
    static let canvas2  = Color(hex: 0xE9A82C)
    static let bg       = Color(hex: 0xFDFAF2) // cream
    static let surface  = Color(hex: 0xFFFFFF)
    static let ink      = Color(hex: 0x1A1815)
    static let ink2     = Color(hex: 0x4A4640)
    static let ink3     = Color(hex: 0x8A8275)
    static let border   = Color(hex: 0xECE4D2)

    // MARK: Category accents
    static let sky    = Color(hex: 0xBFDDE8)
    static let mint   = Color(hex: 0xB9D9C1)
    static let rose   = Color(hex: 0xE5BCBC)
    static let amber  = Color(hex: 0xF2C254)
    static let lilac  = Color(hex: 0xC9BDDC)

    // MARK: Semantic
    static let fresh  = Color(hex: 0x3D6B4F)
    static let alert  = Color(hex: 0xC84B31)

    // MARK: Corners & strokes
    static let cardRadius: CGFloat = 20
    static let bigCardRadius: CGFloat = 24
    static let pillRadius: CGFloat = 999
    static let strokeWidth: CGFloat = 1.5
    static let chunkyShadowOffset: CGFloat = 5
}

extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}
