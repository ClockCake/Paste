import SwiftUI
import Combine
#if os(macOS)
import AppKit
#endif
// MARK: - 外观模式

enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    #if os(macOS)
    /// 对应的 NSAppearance，system 返回 nil 表示跟随系统
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
    #endif
}

// MARK: - 设置管理器

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    // @AppStorage 在 ObservableObject 中不会稳定触发 objectWillChange，
    // 这里手动发送，确保主题/语言切换能实时刷新 UI。
    @AppStorage("appearanceMode") var appearanceMode: AppearanceMode = .system {
        willSet { objectWillChange.send() }
    }
    @AppStorage("appLanguage") var appLanguage: AppLanguage = .system {
        willSet { objectWillChange.send() }
    }
    @AppStorage("iCloudSyncEnabled") var iCloudSyncPreference: Bool = true {
        willSet { objectWillChange.send() }
    }
    @AppStorage("autoPasteOnDoubleClick") var autoPasteOnDoubleClick: Bool = false {
        willSet { objectWillChange.send() }
    }

    var l: L {
        L(lang: appLanguage.resolved)
    }

    func appearanceDisplayName(_ mode: AppearanceMode) -> String {
        switch mode {
        case .system: return l.appearanceSystem
        case .light: return l.appearanceLight
        case .dark: return l.appearanceDark
        }
    }
}
