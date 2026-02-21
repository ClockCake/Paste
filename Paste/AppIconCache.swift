import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// App 图标双层缓存（内存 + 磁盘），用于 iOS 端显示来源 App 图标
final class AppIconCache {
    static let shared = AppIconCache()

    private let memoryCache = NSCache<NSString, PlatformImage>()
    private let fileManager = FileManager.default
    private let directoryURL: URL

    /// 负缓存：记录查询失败的 bundleID → 时间戳，24h 过期
    private var notFoundCache: [String: Date] = [:]
    private let notFoundExpiry: TimeInterval = 24 * 3600

    private init() {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folderName = Bundle.main.bundleIdentifier ?? "Paste"
        let directory = cachesURL
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("AppIcons", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        directoryURL = directory

        memoryCache.countLimit = 50
        memoryCache.totalCostLimit = 5 * 1024 * 1024
    }

    func image(forKey bundleID: String) -> PlatformImage? {
        if let image = memoryCache.object(forKey: bundleID as NSString) {
            return image
        }

        let url = fileURL(forKey: bundleID)
        guard
            let data = try? Data(contentsOf: url),
            let image = PlatformImage(data: data)
        else {
            return nil
        }

        memoryCache.setObject(image, forKey: bundleID as NSString)
        return image
    }

    func storeIcon(_ data: Data, forKey bundleID: String) {
        let url = fileURL(forKey: bundleID)
        if !fileManager.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }
        if let image = PlatformImage(data: data) {
            memoryCache.setObject(image, forKey: bundleID as NSString)
        }
        notFoundCache.removeValue(forKey: bundleID)
    }

    func markNotFound(_ bundleID: String) {
        notFoundCache[bundleID] = Date()
    }

    func isKnownNotFound(_ bundleID: String) -> Bool {
        guard let recordDate = notFoundCache[bundleID] else { return false }
        return Date().timeIntervalSince(recordDate) < notFoundExpiry
    }

    private func fileURL(forKey bundleID: String) -> URL {
        let safeName = bundleID.replacingOccurrences(of: ".", with: "_")
        return directoryURL.appendingPathComponent("\(safeName).png")
    }
}
