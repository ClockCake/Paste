import AppKit
import Foundation

final class ThumbnailCache {
    private let memoryCache = NSCache<NSString, NSImage>()
    private let fileManager = FileManager.default
    private let directoryURL: URL

    init() {
        let cachesURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let folderName = Bundle.main.bundleIdentifier ?? "Paste"
        let directory = cachesURL
            .appendingPathComponent(folderName, isDirectory: true)
            .appendingPathComponent("Thumbnails", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        directoryURL = directory
    }

    func image(forKey key: String?) -> NSImage? {
        guard let key else { return nil }

        if let image = memoryCache.object(forKey: key as NSString) {
            return image
        }

        let url = fileURL(forKey: key)
        guard
            let data = try? Data(contentsOf: url),
            let image = NSImage(data: data)
        else {
            return nil
        }

        memoryCache.setObject(image, forKey: key as NSString)
        return image
    }

    @discardableResult
    func storeThumbnail(_ data: Data, forKey key: String) -> Int64 {
        let url = fileURL(forKey: key)

        if !fileManager.fileExists(atPath: url.path) {
            try? data.write(to: url, options: .atomic)
        }

        if let image = NSImage(data: data) {
            memoryCache.setObject(image, forKey: key as NSString)
        }

        return Int64(data.count)
    }

    func removeThumbnail(forKey key: String?) {
        guard let key else { return }

        memoryCache.removeObject(forKey: key as NSString)
        try? fileManager.removeItem(at: fileURL(forKey: key))
    }

    private func fileURL(forKey key: String) -> URL {
        directoryURL.appendingPathComponent("\(key).jpg")
    }
}
