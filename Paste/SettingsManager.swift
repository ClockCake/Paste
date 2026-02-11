import SwiftUI
import Combine
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

    /// 对应的 NSAppearance，system 返回 nil 表示跟随系统
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - 设置管理器

@MainActor
final class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    @AppStorage("appearanceMode") var appearanceMode: AppearanceMode = .system
    @AppStorage("appLanguage") var appLanguage: AppLanguage = .system
    @AppStorage("iCloudSyncEnabled") var iCloudSyncPreference: Bool = true
    @AppStorage("autoPasteOnDoubleClick") var autoPasteOnDoubleClick: Bool = false

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
