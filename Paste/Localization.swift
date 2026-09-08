import Foundation

// MARK: - 语言枚举

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
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

enum ResolvedLanguage: Sendable {
    case zh, en
}

// MARK: - 本地化字符串

struct L {
    let lang: ResolvedLanguage

    // 应用标题
    var appTitle: String { "Paste" }

    // 统计信息
    func itemCount(_ count: Int) -> String {
        lang == .zh ? "\(count) 条记录" : "\(count) items"
    }
    var iCloudOn: String { lang == .zh ? "iCloud 已开启" : "iCloud On" }
    var iCloudOff: String { lang == .zh ? "iCloud 已关闭（仅本地）" : "iCloud Off (local only)" }
    var iCloudSyncing: String { lang == .zh ? "iCloud 同步中" : "iCloud Syncing" }
    var iCloudSyncFailed: String { lang == .zh ? "iCloud 同步失败" : "iCloud Sync Failed" }
    func iCloudLastSynced(_ value: String) -> String {
        lang == .zh ? "最近同步：\(value)" : "Last synced: \(value)"
    }
    var iCloudNotSyncedYet: String { lang == .zh ? "尚未完成同步" : "Not synced yet" }
    var iCloudErrorTitle: String { lang == .zh ? "iCloud 同步错误" : "iCloud Sync Error" }
    var iCloudErrorHint: String { lang == .zh ? "查看 iCloud 同步错误详情" : "Show iCloud sync error details" }
    var iCloudErrorUnknown: String { lang == .zh ? "未知错误" : "Unknown error" }

    // 过滤器
    var filterAll: String { lang == .zh ? "全部" : "All" }
    var filterFavorites: String { lang == .zh ? "收藏" : "Favorites" }
    var filterText: String { lang == .zh ? "文本" : "Text" }
    var filterURL: String { "URL" }
    var filterImage: String { lang == .zh ? "图片" : "Image" }

    // 类型标签
    var kindText: String { lang == .zh ? "文本" : "Text" }
    var kindURL: String { "URL" }
    var kindImage: String { lang == .zh ? "图片" : "Image" }

    // 内容元信息
    func characterCount(_ count: Int) -> String {
        lang == .zh ? "\(count) 字符" : "\(count) chars"
    }

    // 操作按钮
    var copy: String { lang == .zh ? "复制" : "Copy" }
    var clearAll: String { lang == .zh ? "清除全部" : "Clear All" }
    var cancel: String { lang == .zh ? "取消" : "Cancel" }
    var clear: String { lang == .zh ? "清除" : "Clear" }
    var delete: String { lang == .zh ? "删除" : "Delete" }
    var favorite: String { lang == .zh ? "收藏" : "Favorite" }
    var unfavorite: String { lang == .zh ? "取消收藏" : "Unfavorite" }

    // 提示文字
    var clearAllConfirmTitle: String {
        lang == .zh ? "确定清除所有剪贴板历史？" : "Clear all clipboard history?"
    }
    var clearAllConfirmMessage: String {
        lang == .zh
            ? "这将删除所有本地历史记录和缓存的缩略图，收藏的记录会保留。"
            : "This removes all local history and cached thumbnails. Favorites are kept."
    }
    var emptyStateTitle: String {
        lang == .zh ? "暂无剪贴板历史" : "No clipboard history yet"
    }
    var emptyStateSubtitle: String {
        return lang == .zh ? "复制文本 / URL / 图片即可开始" : "Copy Text / URL / Image to start."
    }
    var clickToCopy: String {
        return lang == .zh ? "双击复制到剪贴板" : "Double-click to copy"
    }
    var doubleClickToPaste: String {
        lang == .zh ? "双击复制并自动粘贴" : "Double-click to copy and paste"
    }
    var manualImport: String {
        lang == .zh ? "导入剪贴板" : "Import Clipboard"
    }
    var manualImportHint: String {
        lang == .zh ? "手动读取当前剪贴板内容" : "Manually import current clipboard content"
    }
    var importSuccess: String {
        lang == .zh ? "已导入当前剪贴板内容" : "Imported current clipboard content"
    }
    var importNoContent: String {
        lang == .zh ? "当前剪贴板没有可导入内容" : "No importable clipboard content"
    }

    // 相对时间
    var timeJustNow: String { lang == .zh ? "刚刚" : "Just now" }
    func timeMinutesAgo(_ minutes: Int) -> String {
        lang == .zh ? "\(minutes) 分钟前" : "\(minutes)m ago"
    }
    func timeHoursAgo(_ hours: Int) -> String {
        lang == .zh ? "\(hours) 小时前" : "\(hours)h ago"
    }
    var timeYesterday: String { lang == .zh ? "昨天" : "Yesterday" }
    func timeDaysAgo(_ days: Int) -> String {
        lang == .zh ? "\(days) 天前" : "\(days)d ago"
    }
    /// 相对时间描述。`fallbackToDateAfterDays` 指定超过多少天后改用具体日期（nil 表示一直用“x 天前”）
    func relativeTimeSince(
        _ date: Date,
        now: Date = Date(),
        fallbackToDateAfterDays: Int? = nil
    ) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60 {
            return timeJustNow
        } else if interval < 3600 {
            let minutes = max(Int(interval / 60), 1)
            return timeMinutesAgo(minutes)
        } else if interval < 86400 {
            let hours = max(Int(interval / 3600), 1)
            return timeHoursAgo(hours)
        } else {
            let days = max(Int(interval / 86400), 1)
            if days == 1 {
                return timeYesterday
            }
            if let threshold = fallbackToDateAfterDays, days >= threshold {
                return DayFormatter.string(from: date, lang: lang)
            }
            return timeDaysAgo(days)
        }
    }

    // 设置相关
    var appearance: String { lang == .zh ? "外观" : "Appearance" }
    var language: String { lang == .zh ? "语言" : "Language" }
    var iCloudSync: String { lang == .zh ? "iCloud 同步" : "iCloud Sync" }
    var autoPasteOnDoubleClick: String {
        lang == .zh ? "双击自动粘贴" : "Auto paste on double-click"
    }
    var autoPasteOnDoubleClickHint: String {
        lang == .zh
            ? "双击后自动粘贴到当前光标处（需开启\u{300C}辅助功能\u{300D}权限）"
            : "Auto paste to the focused field after double-click (requires Accessibility permission)"
    }
    var accessibilityPermissionTitle: String {
        lang == .zh ? "需要辅助功能权限" : "Accessibility Permission Required"
    }
    var accessibilityPermissionMessage: String {
        lang == .zh
            ? "自动粘贴功能需要\u{300C}辅助功能\u{300D}权限来模拟键盘输入。\n\n请前往「系统设置 → 隐私与安全性 → 辅助功能」，找到 Paste 并开启开关。\n如果列表中没有 Paste，请点击「+」按钮手动添加。"
            : "Auto paste needs Accessibility permission to simulate keyboard input.\n\nGo to System Settings → Privacy & Security → Accessibility, find Paste and enable the toggle.\nIf Paste is not listed, click the \"+\" button to add it manually."
    }
    var iCloudRestartHint: String {
        lang == .zh ? "切换后需要重启应用生效" : "Restart app to apply changes"
    }
    var appearanceSystem: String { lang == .zh ? "跟随系统" : "System" }
    var appearanceLight: String { lang == .zh ? "浅色" : "Light" }
    var appearanceDark: String { lang == .zh ? "深色" : "Dark" }

    // 搜索
    var search: String { lang == .zh ? "搜索" : "Search" }
    var keyboardHint: String {
        lang == .zh
            ? "↩ 复制 · ⌘1–9 快捷复制 · ⌫ 删除 · ⌘F 搜索"
            : "↩ Copy · ⌘1–9 Quick copy · ⌫ Delete · ⌘F Search"
    }
    var searchPlaceholder: String { lang == .zh ? "搜索剪贴板内容…" : "Search clipboard..." }
    var noSearchResults: String { lang == .zh ? "无搜索结果" : "No results found" }
    var noSearchResultsHint: String { lang == .zh ? "尝试其他关键词" : "Try different keywords" }

    // 时间筛选
    var timeFilterLabel: String { lang == .zh ? "按时间筛选" : "Filter by Time" }
    var timeFilterAll: String { lang == .zh ? "全部时间" : "All Time" }
    var timeFilterToday: String { lang == .zh ? "今天" : "Today" }
    var timeFilter7Days: String { lang == .zh ? "最近 7 天" : "Last 7 Days" }
    var timeFilter30Days: String { lang == .zh ? "最近 30 天" : "Last 30 Days" }
    var timeFilterCustom: String { lang == .zh ? "自定义日期" : "Custom Date" }

    // 日历选择器 & 批量删除
    var deleteByDate: String { lang == .zh ? "按日期删除" : "Delete by Date" }
    var selectDateRange: String { lang == .zh ? "选择日期范围" : "Select Date Range" }
    var startDate: String { lang == .zh ? "开始日期" : "Start Date" }
    var endDate: String { lang == .zh ? "结束日期" : "End Date" }
    var applyFilter: String { lang == .zh ? "应用筛选" : "Apply" }
    var deleteConfirmByDate: String {
        lang == .zh ? "确定删除所选日期范围的记录？" : "Delete records in selected date range?"
    }
    func deleteConfirmByDateMessage(_ count: Int) -> String {
        lang == .zh
            ? "将删除 \(count) 条记录（不含收藏），此操作不可撤销。"
            : "Will delete \(count) records, excluding favorites. This cannot be undone."
    }
    var noRecordsInRange: String {
        lang == .zh ? "所选日期范围内没有可删除的记录" : "No deletable records in selected range"
    }
    func customDateRangeLabel(from: Date, to: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = lang == .zh ? "M月d日" : "MMM d"
        return "\(formatter.string(from: from)) ~ \(formatter.string(from: to))"
    }
    func deleteSuccess(_ count: Int) -> String {
        lang == .zh ? "已删除 \(count) 条记录" : "Deleted \(count) records"
    }

    // 快捷删除选项
    var deleteManage: String { lang == .zh ? "删除管理" : "Delete" }
    var deleteBeforeWeek: String { lang == .zh ? "一周前的记录" : "Before 1 Week" }
    var deleteBeforeHalfMonth: String { lang == .zh ? "半个月前的记录" : "Before 15 Days" }
    var deleteBeforeMonth: String { lang == .zh ? "一个月前的记录" : "Before 1 Month" }
    var deleteBefore3Months: String { lang == .zh ? "三个月前的记录" : "Before 3 Months" }
    func deleteBeforeConfirm(_ label: String, _ count: Int) -> String {
        lang == .zh ? "确定删除\(label)？共 \(count) 条记录（不含收藏），此操作不可撤销。"
                    : "Delete \(label)? \(count) records will be removed, excluding favorites. This cannot be undone."
    }

    // 选择文本
    var selectText: String { lang == .zh ? "选择文本" : "Select Text" }
    var textContent: String { lang == .zh ? "文本内容" : "Text Content" }
    var done: String { lang == .zh ? "完成" : "Done" }

    // 设置页面
    var settings: String { lang == .zh ? "设置" : "Settings" }
    var generalSection: String { lang == .zh ? "通用" : "General" }
    var clipboardSection: String { lang == .zh ? "剪贴板" : "Clipboard" }
    var syncSection: String { lang == .zh ? "同步" : "Sync" }
    var openURLOnDoubleClick: String { lang == .zh ? "双击 URL 自动打开浏览器" : "Open URL in browser on double-click" }

    // 快捷键设置
    var hotkeyTitle: String { lang == .zh ? "全局快捷键" : "Global Hotkey" }

    // 智能内容识别
    var smartColor: String { lang == .zh ? "颜色" : "Color" }
    var smartPhone: String { lang == .zh ? "电话号码" : "Phone" }
    var smartEmail: String { lang == .zh ? "邮箱" : "Email" }
    var hotkeyCurrentLabel: String { lang == .zh ? "当前快捷键" : "Current Hotkey" }
    var hotkeyNotSet: String { lang == .zh ? "未设置" : "Not Set" }
    var hotkeyRecord: String { lang == .zh ? "录制快捷键" : "Record Hotkey" }
    var hotkeyRecording: String { lang == .zh ? "录制中…" : "Recording…" }
    var hotkeyClear: String { lang == .zh ? "清除" : "Clear" }
    var hotkeyHint: String { lang == .zh ? "设置后可在后台通过快捷键唤起窗口" : "Use hotkey to show window from background" }
    var hotkeyRecordingHint: String { lang == .zh ? "请按下你想要的组合键（需包含修饰键）" : "Press your desired key combination (with modifier)" }
    var hotkeySettings: String { lang == .zh ? "快捷键" : "Hotkey" }

    // 状态栏菜单
    var openWindow: String { lang == .zh ? "打开 Paste" : "Open Paste" }
    var showWindow: String { lang == .zh ? "显示窗口" : "Show Window" }
    var quit: String { lang == .zh ? "退出" : "Quit" }
}

// MARK: - 日期格式化

/// 按语言缓存的 DateFormatter。DateFormatter 初始化昂贵，必须复用
enum DayFormatter {
    private static let zh: DateFormatter = make(format: "M月d日")
    private static let en: DateFormatter = make(format: "MMM d")

    static func string(from date: Date, lang: ResolvedLanguage) -> String {
        (lang == .zh ? zh : en).string(from: date)
    }

    private static func make(format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = format
        return formatter
    }
}
