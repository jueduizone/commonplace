import SwiftUI

/// Pocket Field Notes: the existing Commonplace palette, with native adaptive controls.
enum PaperTheme {
    static let paper = adaptive(0xF5EFE3, 0x1A1714)
    static let panel = adaptive(0xEAE2D2, 0x26211D)
    static let ink = adaptive(0x2A2420, 0xE9DFCC)
    static let secondary = adaptive(0x5E544A, 0xBFB3A0)
    static let rubric = adaptive(0x8B2E1F, 0xE39A84)
    static let unverified = adaptive(0xA3561B, 0xF2B47E)
    static let rule = adaptive(0xD6CAB6, 0x3E3730)
    static func reading(_ size: CGFloat = 18) -> Font { .custom("Literata-Regular", size: size, relativeTo: .body) }
    static let title: Font = .custom("Literata-Regular", size: 30, relativeTo: .largeTitle).weight(.semibold)

    private static func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}
