import Foundation

// MARK: - 语言枚举

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case zh
    case en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return resolved == .zh ? "跟随系统" : "System"
        case .zh: return "中文"
        case .en: return "English"
        }
    }

    var resolved: ResolvedLanguage {
        switch self {
        case .system:
            let preferredLang = Locale.preferredLanguages.first ?? "en"
            return preferredLang.hasPrefix("zh") ? .zh : .en
        case .zh: return .zh
        case .en: return .en
        }
    }
}

enum ResolvedLanguage {
    case zh, en
}

// MARK: - 本地化字符串

struct L {
    let lang: ResolvedLanguage

    // 应用标题
    var appTitle: String { "Paste" }
    var appSubtitle: String {
        lang == .zh ? "自动捕获剪贴板，支持 iCloud 同步" : "Auto capture clipboard with iCloud sync"
    }

    // 统计信息
    func itemCount(_ count: Int) -> String {
        lang == .zh ? "\(count) 条记录" : "\(count) items"
    }
    var iCloudOn: String { lang == .zh ? "iCloud 已开启" : "iCloud On" }
    var iCloudOff: String { lang == .zh ? "iCloud 已关闭（仅本地）" : "iCloud Off (local only)" }

    // 过滤器
    var filterAll: String { lang == .zh ? "全部" : "All" }
    var filterText: String { lang == .zh ? "文本" : "Text" }
    var filterURL: String { "URL" }
    var filterImage: String { lang == .zh ? "图片" : "Image" }

    // 类型标签
    var kindText: String { lang == .zh ? "文本" : "Text" }
    var kindURL: String { "URL" }
    var kindImage: String { lang == .zh ? "图片" : "Image" }

    // 操作按钮
    var clearAll: String { lang == .zh ? "清除全部" : "Clear All" }
    var cancel: String { lang == .zh ? "取消" : "Cancel" }
    var clear: String { lang == .zh ? "清除" : "Clear" }
    var delete: String { lang == .zh ? "删除" : "Delete" }

    // 提示文字
    var clearAllConfirmTitle: String {
        lang == .zh ? "确定清除所有剪贴板历史？" : "Clear all clipboard history?"
    }
    var clearAllConfirmMessage: String {
        lang == .zh ? "这将删除所有本地历史记录和缓存的缩略图。" : "This removes all local history and cached thumbnails."
    }
    var emptyStateTitle: String {
        lang == .zh ? "暂无剪贴板历史" : "No clipboard history yet"
    }
    var emptyStateSubtitle: String {
        lang == .zh ? "复制文本 / URL / 图片即可开始" : "Copy Text / URL / Image to start."
    }
    var clickToCopy: String {
        lang == .zh ? "点击复制到剪贴板" : "Click to copy back to clipboard"
    }

    // 设置相关
    var appearance: String { lang == .zh ? "外观" : "Appearance" }
    var language: String { lang == .zh ? "语言" : "Language" }
    var iCloudSync: String { lang == .zh ? "iCloud 同步" : "iCloud Sync" }
    var iCloudRestartHint: String {
        lang == .zh ? "切换后需要重启应用生效" : "Restart app to apply changes"
    }
    var appearanceSystem: String { lang == .zh ? "跟随系统" : "System" }
    var appearanceLight: String { lang == .zh ? "浅色" : "Light" }
    var appearanceDark: String { lang == .zh ? "深色" : "Dark" }
}
