import SwiftUI

/// The single source of truth for the app's visual language, ported from the
/// "Main Interface UI Design" (Tailwind theme tokens). Warm, calm, high-contrast.
enum Theme {
    // Surfaces
    static let background = Color(hex: 0xFAF8F5)
    static let card = Color(hex: 0xFFFFFF)
    static let muted = Color(hex: 0xF2EFE9)
    static let border = Color(hex: 0xE8E3DC)

    // Text
    static let foreground = Color(hex: 0x2A2825)
    static let secondaryText = Color(hex: 0x6B6762)
    static let mutedText = Color(hex: 0x9A9590)

    // Brand
    static let sage = Color(hex: 0x7BA79B)          // primary
    static let sageSoft = Color(hex: 0xEAF3F0)      // sage tint background
    static let tan = Color(hex: 0xC5B89A)           // accent
    static let tanSoft = Color(hex: 0xF5F0E8)       // tan tint background
    static let coral = Color(hex: 0xD98C8C)         // "not yet happened" status dot

    // Night mode
    static let nightBackground = Color(hex: 0x1A1E2A)
    static let nightForeground = Color(hex: 0xF5F3EF)

    // Corner radii (from --radius tokens)
    static let cardRadius: CGFloat = 24
    static let controlRadius: CGFloat = 18
    static let sheetRadius: CGFloat = 28

    /// The app leans on the rounded system face to echo the friendly, geometric
    /// feel of Inter while staying fully Dynamic-Type aware.
    static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }
}

// MARK: - Reusable building blocks

/// The standard white rounded card with the design's soft drop shadow.
struct RippleCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.cardRadius
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 6, y: 1)
    }
}

/// A tinted circle holding an SF Symbol — the design's recurring icon chip.
struct IconChip: View {
    let systemName: String
    var diameter: CGFloat = 40
    var background: Color
    var tint: Color

    var body: some View {
        Image(systemName: systemName)
            .font(.system(size: diameter * 0.44, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: diameter, height: diameter)
            .background(background, in: Circle())
    }
}

/// The filled sage call-to-action used across steps, calls, and night mode.
struct ProminentButtonStyle: ButtonStyle {
    var fill: Color = Theme.sage
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(17, .semibold))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

/// The quiet muted-fill secondary action ("Say that again", "Call …").
struct SoftButtonStyle: ButtonStyle {
    var fill: Color = Theme.muted
    var foreground: Color = Theme.foreground

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.font(16, .medium))
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(fill, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}
