import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

/// App 图标获取核心：macOS 走 NSWorkspace，iOS 走缓存 + iTunes API
@MainActor
final class AppIconProvider {
    static let shared = AppIconProvider()

    private let cache = AppIconCache.shared
    /// 正在进行中的请求，避免同一 bundleID 并发
    private var inFlightRequests: Set<String> = []

    private init() {}

    // MARK: - 同步获取（仅缓存）

    func cachedIcon(for bundleID: String) -> PlatformImage? {
        guard !isSentinelBundleID(bundleID) else { return nil }

        #if os(macOS)
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: appURL.path)
        #else
        return cache.image(forKey: bundleID)
        #endif
    }

    // MARK: - 异步获取（iTunes API）

    #if os(iOS)
    /// 异步获取图标，缓存未命中时尝试 iTunes Lookup API
    func fetchIconIfNeeded(for bundleID: String) async -> PlatformImage? {
        guard !isSentinelBundleID(bundleID) else { return nil }

        if let cached = cachedIcon(for: bundleID) {
            return cached
        }

        if cache.isKnownNotFound(bundleID) {
            return nil
        }

        guard !inFlightRequests.contains(bundleID) else { return nil }
        inFlightRequests.insert(bundleID)
        defer { inFlightRequests.remove(bundleID) }

        // 尝试所有可能的 bundleID（原始 + macOS→iOS 映射）
        let candidates = allBundleIDCandidates(for: bundleID)

        for candidate in candidates {
            if let image = await fetchFromiTunes(bundleID: candidate, cacheKey: bundleID) {
                return image
            }
        }

        cache.markNotFound(bundleID)
        return nil
    }

    private func fetchFromiTunes(bundleID: String, cacheKey: String) async -> PlatformImage? {
        let regions = ["cn", "us"]

        for region in regions {
            guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleID)&country=\(region)") else {
                continue
            }

            do {
                let (data, response) = try await URLSession.shared.data(from: url)
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    continue
                }

                guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let results = json["results"] as? [[String: Any]],
                      let firstResult = results.first,
                      let artworkURLString = firstResult["artworkUrl100"] as? String,
                      let artworkURL = URL(string: artworkURLString) else {
                    continue
                }

                let (imageData, imageResponse) = try await URLSession.shared.data(from: artworkURL)
                guard let imageHTTPResponse = imageResponse as? HTTPURLResponse,
                      imageHTTPResponse.statusCode == 200,
                      PlatformImage(data: imageData) != nil else {
                    continue
                }

                cache.storeIcon(imageData, forKey: cacheKey)
                return cache.image(forKey: cacheKey)
            } catch {
                continue
            }
        }

        return nil
    }
    #endif

    // MARK: - BundleID 映射

    private func allBundleIDCandidates(for bundleID: String) -> [String] {
        var candidates = [bundleID]
        if let mapped = macToIOSBundleIDMap[bundleID] {
            candidates.append(mapped)
        }
        return candidates
    }

    /// macOS bundleID → iOS bundleID（iCloud 同步的条目可能携带 macOS 端 bundleID）
    private let macToIOSBundleIDMap: [String: String] = [
        "com.apple.Safari":         "com.apple.mobilesafari",
        "com.apple.Notes":          "com.apple.mobilenotes",
        "com.apple.mail":           "com.apple.mobilemail",
        "com.apple.iChat":          "com.apple.MobileSMS",
        "com.apple.Photos":         "com.apple.mobileslideshow",
        "com.google.Chrome":        "com.google.chrome.ios",
        "org.mozilla.firefox":      "org.mozilla.ios.Firefox",
        "com.microsoft.VSCode":     "com.microsoft.VSCode",
        "com.microsoft.Word":       "com.microsoft.Office.Word",
        "com.microsoft.Excel":      "com.microsoft.Office.Excel",
        "com.microsoft.Powerpoint": "com.microsoft.Office.Powerpoint",
        "com.tencent.xinWeChat":    "com.tencent.xin",
    ]

    // MARK: - 辅助

    private func isSentinelBundleID(_ bundleID: String) -> Bool {
        bundleID == "system.pasteboard" ||
        bundleID == "unknown.bundle" ||
        bundleID.isEmpty
    }
}
