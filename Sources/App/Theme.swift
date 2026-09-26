import SwiftUI

/// Consumer design tokens (mockups in the redesign: warm coral accent, cream surfaces).
enum Theme {
    /// Warm coral #EF5A43 (also the asset catalog AccentColor).
    static let coral = Color(red: 0xEF / 255, green: 0x5A / 255, blue: 0x43 / 255)
    static let coralDeep = Color(red: 0xD9 / 255, green: 0x3F / 255, blue: 0x2E / 255)
    static let coralSoft = Color(red: 0xFD / 255, green: 0xE8 / 255, blue: 0xE3 / 255)
    static let cream = Color(red: 0xFA / 255, green: 0xF6 / 255, blue: 0xF1 / 255)

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
        ZStack {
            Theme.coralGradient
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
