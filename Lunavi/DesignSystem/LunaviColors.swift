import SwiftUI
import UIKit

extension UIColor {
    convenience init(lunaviHex hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension Color {
    init(lunaviHex hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// Resolves to `light` or `dark` with the interface style.
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .light ? UIColor(lunaviHex: light) : UIColor(lunaviHex: dark)
        })
    }
}

/// Role-based colour tokens — the single place the interface's colours are defined.
///
/// Dark values are the black mission-control palette: near-black surfaces, gold for the Sun,
/// soft blue for Earth, coral for obstructions and a desaturated sage-grey for valid status.
/// No green or teal surfaces. Light values are kept for later; the app currently runs in dark mode.
///
/// Contrast (WCAG 2.x, measured on the dark surfaces): primary text ≥ 13.9:1, secondary ≥ 6.2:1,
/// Sun ≥ 8.3:1, Earth ≥ 7.2:1, warning ≥ 5.8:1, valid ≥ 7.2:1. The specified muted grey #777D86 is
/// 4.48:1 on the inspector and 4.12:1 on cards, below 4.5:1 for small text, so muted *text* uses
/// #868C95 (≥ 5.0:1 on cards) and #777D86 is kept for non-text details (`detailMuted`).
enum LunaviColors {
    // MARK: Surfaces
    /// Main background behind the map and timeline.
    static let background = Color(light: 0xF5F2EA, dark: 0x08090B)
    /// Top navigation bar.
    static let navigationBar = Color(light: 0xEFEADF, dark: 0x0D0F12)
    /// Right inspector and sheets.
    static let backgroundSecondary = Color(light: 0xEFEADF, dark: 0x111317)
    /// Cards.
    static let surfaceElevated = Color(light: 0xEAE4D8, dark: 0x191C21)
    /// Raised controls on cards (selected segments, pressed states).
    static let surfaceRaised = Color(light: 0xE0D9CB, dark: 0x22262C)
    /// Shown behind the basemap while it loads.
    static let mapBasalt = Color(light: 0xD8D3C7, dark: 0x101215)
    static let border = Color(light: 0xCBC3B3, dark: 0x30343A)
    static let mapPlate = Color(light: 0xF5F2EA, dark: 0x08090B).opacity(0.86)

    // MARK: Text
    static let textPrimary = Color(light: 0x232924, dark: 0xF5F5F5)
    static let textSecondary = Color(light: 0x434B46, dark: 0xA1A6AD)
    static let textMuted = Color(light: 0x59625D, dark: 0x868C95)
    /// Non-text details (tick marks, inactive glyph strokes).
    static let detailMuted = Color(light: 0x6E7672, dark: 0x777D86)

    // MARK: Semantics
    /// Selected time / active location / Sun (gold).
    static let selectedTime = Color(light: 0x8A5A10, dark: 0xE9B866)
    static let activeSite = selectedTime
    /// Valid status (desaturated sage-grey; never used as a large fill).
    static let success = Color(light: 0x3B6A4C, dark: 0xA5B7A9)
    /// Failed condition — text and icons.
    static let failure = Color(light: 0x9E4335, dark: 0xE48778)
    /// Failed condition — fills.
    static let failureFill = Color(light: 0x9E4335, dark: 0xE48778)
    static let unknown = textMuted

    // MARK: Actions
    /// Primary action: near-white fill with near-black label (18:1). Replaces the former pine green.
    static let primaryActionFill = Color(light: 0x232924, dark: 0xF5F5F5)
    static let primaryActionText = Color(light: 0xF5F2EA, dark: 0x08090B)

    // MARK: Timeline
    static let sunTrack = Color(lunaviHex: 0xE9B866)
    static let earthTrack = Color(light: 0x4E6A79, dark: 0x89B9D3)
    static let obstructionTrack = Color(light: 0x9E4335, dark: 0xE48778)

    // MARK: Map markers
    static let alternativeSite = Color(light: 0x3B6A4C, dark: 0xA5B7A9)
    static let unselectedSite = Color(light: 0x6E7672, dark: 0x9AA0A8)

    // MARK: Terrain charts (grayscale)
    static let terrainFill = Color(lunaviHex: 0x4A4F57)
    static let terrainEdge = Color(lunaviHex: 0xC9CDD3)
    static let terrainCanvas = Color(lunaviHex: 0x050607)
    static let terrainSilhouette = Color(lunaviHex: 0x2E3238)
}
