import Foundation
import AppKit

/// App 图标获取核心：按 bundleID 走 NSWorkspace 取本地 App 图标
///
/// 卡片的 body 每次求值都会取图标，直查 NSWorkspace 会反复访问 LaunchServices
/// 和磁盘，滚动长列表时明显掉帧，因此在内存里缓存结果（含查不到的情况）
@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    /// value 为 nil 表示该 bundleID 确认查不到图标，无需再查
    private var iconCache: [String: PlatformImage?] = [:]

    private init() {}

    func cachedIcon(for bundleID: String) -> PlatformImage? {
        guard !isSentinelBundleID(bundleID) else { return nil }

        if let cached = iconCache[bundleID] {
            return cached
        }

        let icon = loadIcon(for: bundleID)
        iconCache[bundleID] = icon
        return icon
    }

    private func loadIcon(for bundleID: String) -> PlatformImage? {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
    }

    private func isSentinelBundleID(_ bundleID: String) -> Bool {
        bundleID == "system.pasteboard" ||
        bundleID == "unknown.bundle" ||
        bundleID.isEmpty
    }
}
