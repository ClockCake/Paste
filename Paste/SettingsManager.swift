import SwiftUI

// MARK: - 外观模式

enum AppearanceMode: String, CaseIterable, Identifiable {
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
}

// MARK: - 设置管理器

@MainActor
final class SettingsManager: ObservableObject {
    @AppStorage("appearanceMode") var appearanceMode: AppearanceMode = .system
    @AppStorage("appLanguage") var appLanguage: AppLanguage = .system
    @AppStorage("iCloudSyncEnabled") var iCloudSyncPreference: Bool = true

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
