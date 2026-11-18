import SwiftUI
import UIKit

/// Design tokens from the "Віджет відключень світла" canvas. Each colour has a light and a dark value.
enum Theme {
    static let bg = dynamic(0xF4F3EF, 0x0F1115)
    static let surface = dynamic(0xFFFFFF, 0x1A1D23)
    static let surface2 = dynamic(0xEFEDE7, 0x252930)
    static let border = dynamic(0xE2DFD7, 0x30353E)
    static let fg = dynamic(0x1C1B18, 0xF3F1EA)
    static let muted = dynamic(0x57544C, 0xB3AFA5)
    static let subtle = dynamic(0x6F6C63, 0x959188)

    /// Power is on.
    static let on = dynamic(0xF2B705, 0xFFC928)
    static let onSoft = dynamic(0xFFF3C4, 0x3A2F0A)
    static let onText = dynamic(0x7A5200, 0xFFD75E)
    /// Power is off.
    static let off = dynamic(0x26344F, 0x4A5674)
    static let offSoft = dynamic(0xE5E9F1, 0x1F2638)
    static let offText = dynamic(0x26344F, 0xB4C0DE)
    /// Background between hatch stripes for "possible outage".
    static let maybeBg = dynamic(0xDCD8CE, 0x2A2F38)

    static let primary = dynamic(0x1C1B18, 0xFFC928)
    static let primaryFg = dynamic(0xFFFFFF, 0x1A1500)
    static let danger = dynamic(0xB42318, 0xFF8A7A)

    static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
        Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
