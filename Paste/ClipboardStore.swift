import AppKit
import Combine
import CoreData
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    private var filter: ClipboardFilter = .all
    private var searchText: String = ""
    private var timeFilter: TimeFilter = .all

    @Published private(set) var cards: [ClipboardCard] = []
    @Published private(set) var totalItems: Int = 0
    @Published private(set) var totalStorageBytes: Int64 = 0

    let cloudSyncEnabled: Bool
    let cloudSyncErrorMessage: String?

    private let maxStorageBytes: Int64 = 2 * 1024 * 1024 * 1024

    private let persistence: PersistenceController
    private let context: NSManagedObjectContext
    private let thumbnailCache: ThumbnailCache

    private var monitor: ClipboardMonitor?
    private var observers: [NSObjectProtocol] = []
    private var started = false
    private var reloadScheduled = false

    init(persistence: PersistenceController) {
        self.persistence = persistence
        context = persistence.container.viewContext
        thumbnailCache = persistence.thumbnailCache
        cloudSyncEnabled = persistence.cloudSyncEnabled
        cloudSyncErrorMessage = persistence.cloudSyncErrorMessage

        registerObservers()
        reloadCards()
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
    }

    func stop() {
        monitor?.stop()
        monitor = nil
        started = false
    }

    func thumbnail(forKey key: String?) -> NSImage? {
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

    func copy(_ card: ClipboardCard) {
        guard let item = fetchItem(id: card.id) else { return }

        let pasteboard = NSPasteboard.general
        monitor?.skipNextCapture()
        pasteboard.clearContents()

        switch item.kind {
        case .text:
            if let text = item.textContent {
                pasteboard.setString(text, forType: .string)
            }
        case .url:
            if let urlString = item.urlString, let url = URL(string: urlString) {
                pasteboard.writeObjects([url as NSURL])
                pasteboard.setString(urlString, forType: .string)
            } else if let urlString = item.urlString {
                pasteboard.setString(urlString, forType: .string)
            }
        case .image:
            if let imageData = item.imageData, let image = NSImage(data: imageData) {
                pasteboard.writeObjects([image])
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

    private func registerObservers() {
        let center = NotificationCenter.default

        let contextObserver = center.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: .main
        ) { [weak self] _ in
            // 延迟执行避免在视图更新期间发布变更
            Task { @MainActor in
                self?.scheduleReload()
            }
        }

        let remoteObserver = center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.scheduleReload()
            }
        }

        observers = [contextObserver, remoteObserver]
    }

    private func save(payload: ClipboardPayload, sourceApp: SourceApplicationInfo) {
        let now = Date()
        let request = ClipboardItem.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "contentHash == %@", payload.contentHash)

        let item: ClipboardItem
        if let existing = try? context.fetch(request).first {
            item = existing
        } else {
            item = ClipboardItem(context: context)
            item.id = UUID()
            item.contentHash = payload.contentHash
        }

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
            thumbnailCache.removeThumbnail(forKey: item.thumbnailKey)
            item.thumbnailKey = nil
            item.thumbnailBytes = 0
            item.imageData = nil
        }

        saveContext()
        pruneIfNeeded()
        scheduleReload()
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
            if item.kind == .image, let imageData = item.imageData, let image = NSImage(data: imageData) {
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
}
