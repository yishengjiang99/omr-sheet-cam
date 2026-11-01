import SwiftUI

/// Host-supplied look for the scan UI. omr-sheet-cam keeps the defaults (coral on near-black);
/// gbk passes its accent. Colors are explicit (not asset-catalog lookups) so a host that locks
/// light mode still gets the intended card colors.
public struct ScanTheme: Sendable {
    public var accent: Color
    public var background: Color
    public var cardBackground: Color
    public var foreground: Color
    /// The non-reading screens of `OMRScanFlow` (choose / done / error).
    /// A ShapeStyle (Color or gradient) so hosts with gradient backgrounds fit.
    public var sheetBackground: AnyShapeStyle
    public var sheetText: Color
    public var sheetSecondaryText: Color
    public var sheetSurface: Color
    public var sheetBorder: Color
    public var destructive: Color

    public init(
        accent: Color = Color(red: 0xEF / 255, green: 0x5A / 255, blue: 0x43 / 255),
        background: Color = Color(white: 0.07),
        cardBackground: Color = .white.opacity(0.1),
        foreground: Color = .white,
        sheetBackground: AnyShapeStyle = AnyShapeStyle(Color(white: 0.97)),
        sheetText: Color = .black,
        sheetSecondaryText: Color = Color(white: 0.4),
        sheetSurface: Color = .white,
        sheetBorder: Color = Color(white: 0.85),
        destructive: Color = .red
    ) {
        self.sheetBackground = sheetBackground; self.sheetText = sheetText
        self.sheetSecondaryText = sheetSecondaryText; self.sheetSurface = sheetSurface
        self.sheetBorder = sheetBorder; self.destructive = destructive
        self.accent = accent
        self.background = background
        self.cardBackground = cardBackground
        self.foreground = foreground
    }

    public static let `default` = ScanTheme()
}

private struct ScanThemeKey: EnvironmentKey {
    static let defaultValue = ScanTheme.default
}

public extension EnvironmentValues {
    var scanTheme: ScanTheme {
        get { self[ScanThemeKey.self] }
        set { self[ScanThemeKey.self] = newValue }
    }
}

public extension View {
    func scanTheme(_ theme: ScanTheme) -> some View { environment(\.scanTheme, theme) }
}
