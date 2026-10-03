import SwiftUI
import UIKit

/// Consumer design tokens (mockups in the redesign: warm coral accent, cream surfaces).
/// Surfaces (`coralSoft`, `cream`) follow the system appearance: light = the mockup colors, dark =
/// warm near-black tints, so `.primary` / `.secondary` text on them stays readable in Dark Mode.
enum Theme {
    /// Warm coral #EF5A43 (also the asset catalog AccentColor).
    static let coral = Color(red: 0xEF / 255, green: 0x5A / 255, blue: 0x43 / 255)
    static let coralDeep = Color(red: 0xD9 / 255, green: 0x3F / 255, blue: 0x2E / 255)
    static let coralSoft = adaptive(light: (0xFD, 0xE8, 0xE3), dark: (0x3A, 0x22, 0x1E))
    static let cream = adaptive(light: (0xFA, 0xF6, 0xF1), dark: (0x1C, 0x19, 0x17))

    /// Light / dark RGB pair resolved by the trait collection (Dark Mode, Increase Contrast keeps these).
    static func adaptive(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
        func ui(_ c: (Int, Int, Int)) -> UIColor {
            UIColor(red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255, blue: CGFloat(c.2) / 255, alpha: 1)
        }
        let l = ui(light), d = ui(dark)
        return Color(UIColor { $0.userInterfaceStyle == .dark ? d : l })
    }

    static let coralGradient = LinearGradient(colors: [Color(red: 0xF7 / 255, green: 0x8A / 255, blue: 0x6B / 255), coral, coralDeep],
                                              startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// Accent-filled capsule button with a soft glow (Result Play, Player play/pause).
struct CoralButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(.white)
            .background(Theme.coralGradient, in: Capsule())
            .shadow(color: Theme.coral.opacity(0.35), radius: 12, y: 4)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

/// Artwork tile: the scan's photo when available, else a coral gradient with a music glyph.
struct ArtworkView: View {
    var image: UIImage?
    var cornerRadius: CGFloat = 12
    var glyphSize: CGFloat = 28

    var body: some View {
        // The gradient takes the proposed size; the photo fills it and is clipped to it.
        Theme.coralGradient
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: glyphSize, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
