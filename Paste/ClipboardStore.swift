import Combine
import CoreData
import CryptoKit
import Foundation
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

@MainActor
final class ClipboardStore: ObservableObject {
    private var filter: ClipboardFilter = .all
    private var searchText: String = ""
    private var timeFilter: TimeFilter = .all

    @Published private(set) var cards: [ClipboardCard] = []
    @Published private(set) var totalItems: Int = 0
    @Published private(set) var totalStorageBytes: Int64 = 0

    @Published private(set) var cloudSyncEnabled: Bool
    @Published private(set) var cloudSyncErrorMessage: String?
    @Published private(set) var cloudSyncInProgress: Bool = false
    @Published private(set) var lastSuccessfulCloudSyncDate: Date?

    private let maxStorageBytes: Int64 = 2 * 1024 * 1024 * 1024

    private let persistence: PersistenceController
    private let context: NSManagedObjectContext
    private let thumbnailCache: ThumbnailCache

    private var monitor: ClipboardMonitor?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var reloadScheduled = false
    private var needsGlobalDedup = true
    #if os(iOS)
    private var iosAutoImportTimer: Timer?
    private var lastObservedPasteboardChangeCount: Int?
    #endif

    init(persistence: PersistenceController) {
        self.persistence = persistence
        context = persistence.container.viewContext
        thumbnailCache = persistence.thumbnailCache
        let syncSnapshot = persistence.cloudSyncStatusSnapshot
        cloudSyncEnabled = syncSnapshot.enabled
        cloudSyncErrorMessage = syncSnapshot.errorMessage
        cloudSyncInProgress = syncSnapshot.inProgress
        lastSuccessfulCloudSyncDate = syncSnapshot.lastSuccessfulSyncDate

        registerObservers()
        reloadCards()
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        #if os(iOS)
        iosAutoImportTimer?.invalidate()
        #endif
    }

    var storageText: String {
        ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file)
    }

    var currentFilter: ClipboardFilter {
        filter
    }

    var currentSearchText: String {
        searchText
    }

    var currentTimeFilter: TimeFilter {
        timeFilter
    }

    func updateFilter(_ newFilter: ClipboardFilter) {
        guard filter != newFilter else { return }
        filter = newFilter
        scheduleReload()
    }

    func updateSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard searchText != trimmed else { return }
        searchText = trimmed
        scheduleReload()
    }

    func updateTimeFilter(_ newFilter: TimeFilter) {
        guard timeFilter != newFilter else { return }
        timeFilter = newFilter
        scheduleReload()
    }

    func start() {
        guard !started else { return }
        started = true

        let monitor = ClipboardMonitor { [weak self] payload, sourceApp in
            self?.save(payload: payload, sourceApp: sourceApp)
        }
        monitor.start()
        self.monitor = monitor
        #if os(iOS)
        startIOSAutoImport()
        #endif
    }

    func stop() {
        #if os(iOS)
        stopIOSAutoImport()
        #endif
        monitor?.stop()
        monitor = nil
        started = false
    }

    func thumbnail(forKey key: String?) -> PlatformImage? {
        // 先尝试从缓存读取
        if let image = thumbnailCache.image(forKey: key) {
            return image
        }
        // 缓存缺失时，从 CoreData 的 imageData 重新生成缩略图
        guard let key else { return nil }
        let request = ClipboardItem.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "thumbnailKey == %@", key)
        guard
            let item = try? context.fetch(request).first,
            let imageData = item.imageData,
            let thumbData = ImageCoder.thumbnailJPEGData(from: imageData)
        else {
            return nil
        }
        thumbnailCache.storeThumbnail(thumbData, forKey: key)
        return thumbnailCache.image(forKey: key)
    }

    func fullImage(for card: ClipboardCard) -> PlatformImage? {
        guard
            let item = fetchItem(id: card.id),
            let imageData = item.imageData
        else {
            return nil
        }
        return PlatformImage(data: imageData)
    }

    func copy(_ card: ClipboardCard) {
        guard let item = fetchItem(id: card.id) else { return }

        #if os(macOS)
        let pasteboard = NSPasteboard.general
        monitor?.skipNextCapture()
        pasteboard.clearContents()
        #elseif os(iOS)
        let pasteboard = UIPasteboard.general
        #endif

        switch item.kind {
        case .text:
            if let text = item.textContent {
                #if os(macOS)
                pasteboard.setString(text, forType: .string)
                #elseif os(iOS)
                pasteboard.string = text
                #endif
            }
        case .url:
            if let urlString = item.urlString, let url = URL(string: urlString) {
                #if os(macOS)
                pasteboard.writeObjects([url as NSURL])
                pasteboard.setString(urlString, forType: .string)
                #elseif os(iOS)
                pasteboard.url = url
                pasteboard.string = urlString
                #endif
            } else if let urlString = item.urlString {
                #if os(macOS)
                pasteboard.setString(urlString, forType: .string)
                #elseif os(iOS)
                pasteboard.string = urlString
                #endif
            }
        case .image:
            if let imageData = item.imageData, let image = PlatformImage(data: imageData) {
                #if os(macOS)
                pasteboard.writeObjects([image])
                #elseif os(iOS)
                pasteboard.image = image
                #endif
            }
        }
    }

    func delete(_ card: ClipboardCard) {
        guard let item = fetchItem(id: card.id) else { return }

        thumbnailCache.removeThumbnail(forKey: item.thumbnailKey)
        context.delete(item)
        saveContext()
        scheduleReload()
    }

    func toggleFavorite(_ card: ClipboardCard) {
        guard let item = fetchItem(id: card.id) else { return }
        item.isFavorite.toggle()
        saveContext()
        scheduleReload()
    }

    func clearAll() {
        let request = ClipboardItem.fetchRequest()
        guard let allItems = try? context.fetch(request) else { return }

        allItems.forEach { item in
            thumbnailCache.removeThumbnail(forKey: item.thumbnailKey)
            context.delete(item)
        }

        saveContext()
        scheduleReload()
    }

    #if os(iOS)
    private func currentPasteboardPayload(from pasteboard: UIPasteboard) -> ClipboardPayload? {
        if let imageData = ImageCoder.normalizedJPEGData(from: pasteboard) {
            return ClipboardPayload(
                kind: .image,
                text: nil,
                urlString: nil,
                imageData: imageData,
                contentHash: contentHash(kind: .image, payload: imageData),
                payloadBytes: Int64(imageData.count)
            )
        }

        if let url = pasteboard.url {
            let urlString = url.absoluteString
            return ClipboardPayload(
                kind: .url,
                text: nil,
                urlString: urlString,
                imageData: nil,
                contentHash: contentHash(kind: .url, payload: Data(urlString.utf8)),
                payloadBytes: Int64(urlString.utf8.count)
            )
        }

        if
            let text = pasteboard.string?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        {
            if let url = URL(string: text), url.scheme != nil {
                return ClipboardPayload(
                    kind: .url,
                    text: nil,
                    urlString: text,
                    imageData: nil,
                    contentHash: contentHash(kind: .url, payload: Data(text.utf8)),
                    payloadBytes: Int64(text.utf8.count)
                )
            }

            return ClipboardPayload(
                kind: .text,
                text: text,
                urlString: nil,
                imageData: nil,
                contentHash: contentHash(kind: .text, payload: Data(text.utf8)),
                payloadBytes: Int64(text.utf8.count)
            )
        }

        return nil
    }
    #endif

    private func registerObservers() {
        let center = NotificationCenter.default

        let contextObserver = center.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: .main
        ) { [weak self] _ in
            // 延迟执行避免在视图更新期间发布变更
            DispatchQueue.main.async { [weak self] in
                self?.scheduleReload()
            }
        }

        let remoteObserver = center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.needsGlobalDedup = true
                self?.scheduleReload()
            }
        }

        let cloudSyncStatusObserver = center.addObserver(
            forName: .cloudSyncStatusDidChange,
            object: persistence,
            queue: .main
        ) { [weak self] notification in
            DispatchQueue.main.async { [weak self] in
                self?.applyCloudSyncStatus(notification)
            }
        }

        var registeredObservers = [contextObserver, remoteObserver, cloudSyncStatusObserver]

        #if os(iOS)
        let didBecomeActiveObserver = center.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.startIOSAutoImport()
        }

        let willResignActiveObserver = center.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.stopIOSAutoImport()
        }

        let pasteboardChangedObserver = center.addObserver(
            forName: UIPasteboard.changedNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard UIApplication.shared.applicationState == .active else { return }
            self?.autoImportFromCurrentPasteboardIfNeeded()
        }

        registeredObservers.append(didBecomeActiveObserver)
        registeredObservers.append(willResignActiveObserver)
        registeredObservers.append(pasteboardChangedObserver)
        #endif

        observers = registeredObservers
    }

    private func applyCloudSyncStatus(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        if let enabled = userInfo[CloudSyncStatusUserInfoKey.enabled] as? Bool {
            cloudSyncEnabled = enabled
        }
        if let inProgress = userInfo[CloudSyncStatusUserInfoKey.inProgress] as? Bool {
            cloudSyncInProgress = inProgress
        }
        if userInfo.keys.contains(CloudSyncStatusUserInfoKey.errorMessage) {
            cloudSyncErrorMessage = userInfo[CloudSyncStatusUserInfoKey.errorMessage] as? String
        }
        if userInfo.keys.contains(CloudSyncStatusUserInfoKey.lastSuccessfulSyncDate) {
            lastSuccessfulCloudSyncDate = userInfo[CloudSyncStatusUserInfoKey.lastSuccessfulSyncDate] as? Date
        }
    }

    #if os(iOS)
    private func startIOSAutoImport() {
        guard UIApplication.shared.applicationState == .active else { return }
        _ = autoImportFromCurrentPasteboardIfNeeded(force: lastObservedPasteboardChangeCount == nil)
        guard iosAutoImportTimer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: 0.9, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.autoImportFromCurrentPasteboardIfNeeded()
            }
        }
        timer.tolerance = 0.2
        iosAutoImportTimer = timer
    }

    private func stopIOSAutoImport() {
        iosAutoImportTimer?.invalidate()
        iosAutoImportTimer = nil
    }

    @discardableResult
    private func autoImportFromCurrentPasteboardIfNeeded(force: Bool = false) -> Bool {
        let pasteboard = UIPasteboard.general
        let currentChangeCount = pasteboard.changeCount
        if !force, let lastObservedPasteboardChangeCount, lastObservedPasteboardChangeCount == currentChangeCount {
            return false
        }
        lastObservedPasteboardChangeCount = currentChangeCount

        guard let payload = currentPasteboardPayload(from: pasteboard) else {
            return false
        }

        let source = SourceApplicationInfo(
            name: "iOS Clipboard",
            bundleID: "system.pasteboard"
        )
        save(payload: payload, sourceApp: source, playFeedback: false)
        return true
    }
    #endif

    private func save(payload: ClipboardPayload, sourceApp: SourceApplicationInfo, playFeedback: Bool = true) {
        let now = Date()
        let request = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "contentHash == %@", payload.contentHash)

        // 去重：如果已存在相同内容，先删除旧条目，再新建
        // 这样新条目的 createdAt 一定是最新的，排序一定在最前面
        if let existingItems = try? context.fetch(request), !existingItems.isEmpty {
            existingItems.forEach { existing in
                thumbnailCache.removeThumbnail(forKey: existing.thumbnailKey)
                context.delete(existing)
            }
        }

        let item = ClipboardItem(context: context)
        item.id = UUID()
        item.contentHash = payload.contentHash

        item.createdAt = now
        item.updatedAt = now
        item.kind = payload.kind
        item.textContent = payload.text
        item.urlString = payload.urlString
        item.imageData = payload.imageData
        item.sourceAppName = sourceApp.name
        item.sourceBundleID = sourceApp.bundleID
        item.payloadBytes = payload.payloadBytes

        if item.kind == .image {
            let key = payload.contentHash
            item.thumbnailKey = key
            if
                let imageData = payload.imageData,
                let thumbnailData = ImageCoder.thumbnailJPEGData(from: imageData)
            {
                item.thumbnailBytes = thumbnailCache.storeThumbnail(thumbnailData, forKey: key)
            } else {
                item.thumbnailBytes = 0
            }
        } else {
            item.thumbnailKey = nil
            item.thumbnailBytes = 0
            item.imageData = nil
        }

        saveContext()
        pruneIfNeeded()
        scheduleReload()

        if playFeedback {
            // 全局复制时播放音效
            SoundManager.playCopySound()
        }
    }

    private func pruneIfNeeded() {
        let request = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        guard let allItems = try? context.fetch(request) else {
            return
        }

        var currentBytes = allItems.reduce(0) { $0 + $1.storageBytes }
        var didDelete = false

        for item in allItems where currentBytes > maxStorageBytes {
            currentBytes -= item.storageBytes
            thumbnailCache.removeThumbnail(forKey: item.thumbnailKey)
            context.delete(item)
            didDelete = true
        }

        if didDelete {
            saveContext()
        }
    }

    private func reloadCards() {
        if needsGlobalDedup {
            deduplicateByContentHash()
            needsGlobalDedup = false
        }

        let request = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        // 构建筛选条件
        var predicates: [NSPredicate] = []

        if filter.isFavoritesFilter {
            predicates.append(NSPredicate(format: "isFavorite == true"))
        }

        if let kind = filter.kind {
            predicates.append(NSPredicate(format: "kindRaw == %@", kind.rawValue))
        }

        // 搜索条件：匹配文本内容或 URL
        if !searchText.isEmpty {
            let searchPredicate = NSPredicate(
                format: "textContent CONTAINS[cd] %@ OR urlString CONTAINS[cd] %@",
                searchText, searchText
            )
            predicates.append(searchPredicate)
        }

        // 时间筛选
        if let startDate = timeFilter.startDate {
            predicates.append(NSPredicate(format: "createdAt >= %@", startDate as NSDate))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        guard let fetched = try? context.fetch(request) else {
            cards = []
            totalItems = 0
            totalStorageBytes = 0
            return
        }

        cards = fetched.map { item in
            // 计算图片尺寸
            var imageWidth: Int?
            var imageHeight: Int?
            if item.kind == .image, let imageData = item.imageData, let image = PlatformImage(data: imageData) {
                imageWidth = Int(image.size.width)
                imageHeight = Int(image.size.height)
            }

            // 智能内容识别（仅文本类型）
            let smartType: SmartContentType = (item.kind == .text)
                ? SmartContentDetector.detect(item.previewText)
                : .none

            return ClipboardCard(
                id: item.id,
                kind: item.kind,
                createdAt: item.createdAt,
                sourceAppName: item.sourceAppName ?? "Unknown",
                sourceBundleID: item.sourceBundleID ?? "unknown.bundle",
                previewText: item.previewText,
                thumbnailKey: item.thumbnailKey,
                isFavorite: item.isFavorite,
                characterCount: item.previewText.count,
                imageWidth: imageWidth,
                imageHeight: imageHeight,
                smartContentType: smartType
            )
        }

        let totalsRequest = ClipboardItem.fetchRequest()
        if let allItems = try? context.fetch(totalsRequest) {
            totalItems = allItems.count
            totalStorageBytes = allItems.reduce(0) { $0 + $1.storageBytes }
        }
    }

    private func scheduleReload() {
        guard !reloadScheduled else { return }
        reloadScheduled = true
        // 使用下一次 RunLoop，避免视图更新期间发布变更
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.reloadScheduled = false
            self.reloadCards()
        }
    }

    private func fetchItem(id: UUID) -> ClipboardItem? {
        let request = ClipboardItem.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        try? context.save()
    }

    private func deduplicateByContentHash() {
        let request = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        guard let allItems = try? context.fetch(request), !allItems.isEmpty else { return }

        var seen = Set<String>()
        var didDelete = false

        for item in allItems {
            let hash = item.contentHash
            guard !hash.isEmpty else { continue }
            if seen.contains(hash) {
                thumbnailCache.removeThumbnail(forKey: item.thumbnailKey)
                context.delete(item)
                didDelete = true
            } else {
                seen.insert(hash)
            }
        }

        if didDelete {
            saveContext()
        }
    }

    private func contentHash(kind: ClipboardEntryKind, payload: Data) -> String {
        var input = Data(kind.rawValue.utf8)
        input.append(payload)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}
