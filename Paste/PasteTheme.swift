import SwiftUI
import AppKit

/// 主窗口与弹出面板共用的配色，随系统或应用内的外观设置切换。
enum PasteTheme {
    static let accent = adaptive(light: 0x247F73, dark: 0x76CDBA)
    static let canvas = adaptive(light: 0xF4F5F3, dark: 0x171C1B)
    static let sidebar = adaptive(light: 0xECEFEB, dark: 0x1C2221)
    static let surface = adaptive(light: 0xFFFFFF, dark: 0x232B29)
    static let inset = adaptive(light: 0xF7F8F6, dark: 0x1E2523)
    static let border = adaptive(light: 0xDDE2DD, dark: 0x35413C)

    private static func adaptive(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let value = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
                green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255,
                alpha: 1
            )
        })
    }
}
