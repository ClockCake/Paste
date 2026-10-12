import Combine
import CoreData
import CryptoKit
import Foundation
import ImageIO
import AppKit

struct ClipboardSnapshot {
    let cards: [ClipboardCard]
    let totalItems: Int
    let totalStorageBytes: Int64
}

enum ClipboardStorageOperations {
    @discardableResult
    nonisolated static func upsertItem(
        payload: ClipboardPayload,
        sourceApp: SourceApplicationInfo,
        at timestamp: Date = Date(),
        in context: NSManagedObjectContext
    ) throws -> (item: ClipboardItem, removedThumbnailKeys: [String]) {
        let request = ClipboardItem.fetchRequest()
        request.predicate = NSPredicate(format: "contentHash == %@", payload.contentHash)

        let existingItems = try context.fetch(request)
        let removedThumbnailKeys = existingItems.compactMap { $0.thumbnailKey }
        // 同内容的旧条目会被删掉重建，收藏标记要跟着带过来，否则重复复制一次收藏就丢了
        let inheritedFavorite = existingItems.contains { $0.isFavorite }
        existingItems.forEach(context.delete)

        let item = ClipboardItem(context: context)
        item.id = UUID()
        item.contentHash = payload.contentHash
        item.createdAt = timestamp
        item.updatedAt = timestamp
        item.kind = payload.kind
        item.textContent = payload.text
        item.urlString = payload.urlString
        item.imageData = payload.imageData
        item.sourceAppName = sourceApp.name
        item.sourceBundleID = sourceApp.bundleID
        item.payloadBytes = payload.payloadBytes
        item.thumbnailKey = nil
        item.thumbnailBytes = 0
        item.isFavorite = inheritedFavorite

        return (item, removedThumbnailKeys)
    }

    nonisolated static func deduplicateItemsByContentHash(in context: NSManagedObjectContext) throws -> [String] {
        let request = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        let allItems = try context.fetch(request)
        guard !allItems.isEmpty else { return [] }

        var groups: [String: [ClipboardItem]] = [:]
        for item in allItems {
            let hash = item.contentHash
            guard !hash.isEmpty else { continue }
            groups[hash, default: []].append(item)
        }

        var removedThumbnailKeys: [String] = []
        for (_, items) in groups where items.count > 1 {
            // 收藏项优先保留；同为收藏或同为非收藏时，再按“来源真实”择优
            let favorites = items.filter { $0.isFavorite }
            let candidates = favorites.isEmpty ? items : favorites
            let keeper = candidates.first(where: isRealSource(_:)) ?? candidates[0]

            for item in items where item !== keeper {
                if let key = item.thumbnailKey {
                    removedThumbnailKeys.append(key)
                }
                context.delete(item)
            }
        }

        return removedThumbnailKeys
    }

    /// 批量删除永不涉及收藏项：收藏的记录只能在卡片上逐条删除。
    /// 所有批量删除入口都必须经由这里取待删条目，规则只在此处定义一次
    nonisolated static var excludeFavoritesPredicate: NSPredicate {
        NSPredicate(format: "isFavorite == false")
    }

    /// 取出符合条件且可被批量删除的条目（自动排除收藏项）
    nonisolated static func itemsForBulkDeletion(
        matching predicate: NSPredicate?,
        in context: NSManagedObjectContext
    ) -> [ClipboardItem] {
        let request = ClipboardItem.fetchRequest()
        request.predicate = bulkDeletionPredicate(combining: predicate)
        return (try? context.fetch(request)) ?? []
    }

    /// 统计符合条件且可被批量删除的条目数（自动排除收藏项）
    nonisolated static func bulkDeletionCount(
        matching predicate: NSPredicate?,
        in context: NSManagedObjectContext
    ) -> Int {
        let request = ClipboardItem.fetchRequest()
        request.predicate = bulkDeletionPredicate(combining: predicate)
        return (try? context.count(for: request)) ?? 0
    }

    nonisolated static func bulkDeletionPredicate(combining predicate: NSPredicate?) -> NSPredicate {
        guard let predicate else { return excludeFavoritesPredicate }
        return NSCompoundPredicate(andPredicateWithSubpredicates: [predicate, excludeFavoritesPredicate])
    }

    nonisolated static func makeSnapshot(
        in context: NSManagedObjectContext,
        filter: ClipboardFilter,
        searchText: String,
        timeFilter: TimeFilter,
        customDateFrom: Date? = nil,
        customDateTo: Date? = nil
    ) throws -> ClipboardSnapshot {
        // 固定本次读取的数据版本，避免其他 context 删除记录后，延迟加载的属性变成 nil。
        // 此方法在专用的后台 context 队列中调用，列表和统计必须使用同一份快照。
        try context.setQueryGenerationFrom(.current)

        let request = makeCardsRequest(
            filter: filter,
            searchText: searchText,
            timeFilter: timeFilter,
            customDateFrom: customDateFrom,
            customDateTo: customDateTo
        )

        let fetched = try context.fetch(request)

        let cards = fetched.compactMap { item -> ClipboardCard? in
            // 经由 KVC 检查底层值，不能先访问非可选的 Swift 属性，否则桥接时就会崩溃。
            guard
                !item.isDeleted,
                let id = item.value(forKey: "id") as? UUID,
                let createdAt = item.value(forKey: "createdAt") as? Date,
                !item.isDeleted
            else {
                return nil
            }

            var imageWidth: Int?
            var imageHeight: Int?
            if item.kind == .image, let imageData = item.imageData,
               let size = imagePixelSize(from: imageData)
            {
                imageWidth = size.width
                imageHeight = size.height
            }

            let smartType: SmartContentType = (item.kind == .text)
                ? SmartContentDetector.detect(item.previewText)
                : .none

            return ClipboardCard(
                id: id,
                kind: item.kind,
                createdAt: createdAt,
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
        let totals = try context.fetch(totalsRequest)

        return ClipboardSnapshot(
            cards: cards,
            totalItems: totals.count,
            totalStorageBytes: totals.reduce(0) { $0 + $1.storageBytes }
        )
    }

    nonisolated private static func makeCardsRequest(
        filter: ClipboardFilter,
        searchText: String,
        timeFilter: TimeFilter,
        customDateFrom: Date? = nil,
        customDateTo: Date? = nil
    ) -> NSFetchRequest<ClipboardItem> {
        let request = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]

        var predicates: [NSPredicate] = []

        if filter.isFavoritesFilter {
            predicates.append(NSPredicate(format: "isFavorite == true"))
        }

        if let kind = filter.kind {
            predicates.append(NSPredicate(format: "kindRaw == %@", kind.rawValue))
        }

        if !searchText.isEmpty {
            let searchPredicate = NSPredicate(
                format: "textContent CONTAINS[cd] %@ OR urlString CONTAINS[cd] %@",
                searchText, searchText
            )
            predicates.append(searchPredicate)
        }

        if timeFilter == .customRange {
            // 自定义日期范围
            if let from = customDateFrom {
                let startOfFrom = Calendar.current.startOfDay(for: from)
                predicates.append(NSPredicate(format: "createdAt >= %@", startOfFrom as NSDate))
            }
            if let to = customDateTo {
                // 结束日期包含当天，所以取下一天的起始
                let nextDay = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: to))!
                predicates.append(NSPredicate(format: "createdAt < %@", nextDay as NSDate))
            }
        } else if let startDate = timeFilter.startDate {
            predicates.append(NSPredicate(format: "createdAt >= %@", startDate as NSDate))
        }

        if !predicates.isEmpty {
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }

        return request
    }

    nonisolated private static func imagePixelSize(from data: Data) -> (width: Int, height: Int)? {
        guard
            let source = CGImageSourceCreateWithData(data as CFData, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
            let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
            let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else {
            return nil
        }

        return (width, height)
    }

    nonisolated private static func isRealSource(_ item: ClipboardItem) -> Bool {
        let bundleID = item.sourceBundleID ?? ""
        return !bundleID.isEmpty && bundleID != "system.pasteboard" && bundleID != "unknown.bundle"
    }
}

@MainActor
final class ClipboardStore: ObservableObject {
    private var filter: ClipboardFilter = .all
    private var searchText: String = ""
    private var timeFilter: TimeFilter = .all
    private var customDateFrom: Date?
    private var customDateTo: Date?

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
    private var reloadWorkItem: DispatchWorkItem?
    private var reloadGeneration: UInt64 = 0
    private var remoteMaintenanceWorkItem: DispatchWorkItem?
    private var remoteMaintenancePending = false
    private var remoteMaintenanceInFlight = false
    private var remoteMaintenanceQueued = false

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
        scheduleReload(delay: 0, ignoreRemoteMaintenance: true)
        if cloudSyncEnabled {
            scheduleRemoteMaintenance()
        }
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        reloadWorkItem?.cancel()
        remoteMaintenanceWorkItem?.cancel()
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

    var currentCustomDateFrom: Date? {
        customDateFrom
    }

    var currentCustomDateTo: Date? {
        customDateTo
    }

    func updateFilter(_ newFilter: ClipboardFilter) {
        guard filter != newFilter else { return }
        filter = newFilter
        scheduleReload(ignoreRemoteMaintenance: true)
    }

    func updateSearch(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard searchText != trimmed else { return }
        searchText = trimmed
        scheduleReload(ignoreRemoteMaintenance: true)
    }

    func updateTimeFilter(_ newFilter: TimeFilter) {
        guard timeFilter != newFilter else { return }
        timeFilter = newFilter
        if newFilter != .customRange {
            customDateFrom = nil
            customDateTo = nil
        }
        scheduleReload(ignoreRemoteMaintenance: true)
    }

    /// 设置自定义日期范围并切换到 customRange 筛选模式
    func updateCustomDateRange(from: Date, to: Date) {
        customDateFrom = from
        customDateTo = to
        timeFilter = .customRange
        scheduleReload(ignoreRemoteMaintenance: true)
    }

    /// 按日期范围批量删除记录，返回删除的记录数（不含收藏项）
    @discardableResult
    func deleteByDateRange(from startDate: Date, to endDate: Date) -> Int {
        performBulkDeletion(matching: Self.dateRangePredicate(from: startDate, to: endDate))
    }

    /// 统计指定日期范围内可批量删除的记录数（不含收藏项）
    func countByDateRange(from startDate: Date, to endDate: Date) -> Int {
        ClipboardStorageOperations.bulkDeletionCount(
            matching: Self.dateRangePredicate(from: startDate, to: endDate),
            in: context
        )
    }

    /// 删除指定日期之前的记录，返回删除数量（不含收藏项）
    @discardableResult
    func deleteRecordsBefore(date: Date) -> Int {
        performBulkDeletion(matching: NSPredicate(format: "createdAt < %@", date as NSDate))
    }

    /// 统计指定日期之前可批量删除的记录数（不含收藏项）
    func countRecordsBefore(date: Date) -> Int {
        ClipboardStorageOperations.bulkDeletionCount(
            matching: NSPredicate(format: "createdAt < %@", date as NSDate),
            in: context
        )
    }

    private static func dateRangePredicate(from startDate: Date, to endDate: Date) -> NSPredicate {
        let calendar = Calendar.current
        let adjustedStart = calendar.startOfDay(for: startDate)
        let adjustedEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: endDate))!
        return NSCompoundPredicate(andPredicateWithSubpredicates: [
            NSPredicate(format: "createdAt >= %@", adjustedStart as NSDate),
            NSPredicate(format: "createdAt < %@", adjustedEnd as NSDate)
        ])
    }

    /// 所有批量删除的统一出口，收藏项由 ClipboardStorageOperations 排除
    @discardableResult
    private func performBulkDeletion(matching predicate: NSPredicate?) -> Int {
        let items = ClipboardStorageOperations.itemsForBulkDeletion(matching: predicate, in: context)
        guard !items.isEmpty else { return 0 }

        items.forEach { item in
            thumbnailCache.removeThumbnail(forKey: item.thumbnailKey)
            context.delete(item)
        }
        saveContext()
        scheduleReload(ignoreRemoteMaintenance: true)
        return items.count
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
            if let imageData = item.imageData, let image = PlatformImage(data: imageData) {
                pasteboard.writeObjects([image])
            }
        }

        bumpItemToFront(item)
    }

    func delete(_ card: ClipboardCard) {
        guard let item = fetchItem(id: card.id) else { return }

        thumbnailCache.removeThumbnail(forKey: item.thumbnailKey)
        context.delete(item)
        saveContext()
        scheduleReload(ignoreRemoteMaintenance: true)
    }

    func toggleFavorite(_ card: ClipboardCard) {
        guard let item = fetchItem(id: card.id) else { return }
        item.isFavorite.toggle()
        saveContext()
        scheduleReload(ignoreRemoteMaintenance: true)
    }

    /// 清除全部历史，收藏项保留
    func clearAll() {
        performBulkDeletion(matching: nil)
    }

    private func registerObservers() {
        let center = NotificationCenter.default

        let contextObserver = center.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.remoteMaintenancePending else { return }
                self.scheduleReload(delay: self.currentReloadDelay())
            }
        }

        let remoteObserver = center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                self?.scheduleRemoteMaintenance()
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

        observers = [contextObserver, remoteObserver, cloudSyncStatusObserver]
    }

    private func applyCloudSyncStatus(_ notification: Notification) {
        guard let userInfo = notification.userInfo else { return }
        if let enabled = userInfo[CloudSyncStatusUserInfoKey.enabled] as? Bool, enabled != cloudSyncEnabled {
            cloudSyncEnabled = enabled
        }
        if let inProgress = userInfo[CloudSyncStatusUserInfoKey.inProgress] as? Bool, inProgress != cloudSyncInProgress {
            cloudSyncInProgress = inProgress
        }
        if userInfo.keys.contains(CloudSyncStatusUserInfoKey.errorMessage) {
            let newError = userInfo[CloudSyncStatusUserInfoKey.errorMessage] as? String
            if newError != cloudSyncErrorMessage {
                cloudSyncErrorMessage = newError
            }
        }
        if userInfo.keys.contains(CloudSyncStatusUserInfoKey.lastSuccessfulSyncDate) {
            let newDate = userInfo[CloudSyncStatusUserInfoKey.lastSuccessfulSyncDate] as? Date
            if newDate != lastSuccessfulCloudSyncDate {
                lastSuccessfulCloudSyncDate = newDate
            }
        }
    }

    private func save(payload: ClipboardPayload, sourceApp: SourceApplicationInfo, playFeedback: Bool = true) {
        do {
            let (item, removedThumbnailKeys) = try ClipboardStorageOperations.upsertItem(
                payload: payload,
                sourceApp: sourceApp,
                in: context
            )
            removedThumbnailKeys.forEach(thumbnailCache.removeThumbnail(forKey:))

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
            scheduleReload(ignoreRemoteMaintenance: true)

            if playFeedback {
                SoundManager.playCopySound()
            }
        } catch {
            return
        }
    }

    /// 超出容量上限时按时间从旧到新清理。收藏项不参与清理，
    /// 因此非收藏记录全部清完后仍可能超限——这是为保住收藏做的让步
    private func pruneIfNeeded() {
        let request = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        guard let allItems = try? context.fetch(request) else {
            return
        }

        var currentBytes = allItems.reduce(0) { $0 + $1.storageBytes }
        var didDelete = false

        for item in allItems where currentBytes > maxStorageBytes {
            guard !item.isFavorite else { continue }
            currentBytes -= item.storageBytes
            thumbnailCache.removeThumbnail(forKey: item.thumbnailKey)
            context.delete(item)
            didDelete = true
        }

        if didDelete {
            saveContext()
        }
    }

    private func reloadCards(
        generation: UInt64,
        filter: ClipboardFilter,
        searchText: String,
        timeFilter: TimeFilter,
        customDateFrom: Date?,
        customDateTo: Date?
    ) {
        let backgroundContext = persistence.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext.undoManager = nil

        backgroundContext.perform { [weak self] in
            let snapshot: ClipboardSnapshot
            do {
                snapshot = try ClipboardStorageOperations.makeSnapshot(
                    in: backgroundContext,
                    filter: filter,
                    searchText: searchText,
                    timeFilter: timeFilter,
                    customDateFrom: customDateFrom,
                    customDateTo: customDateTo
                )
            } catch {
                // 读取失败时保留当前列表，不能继续使用未固定版本的 context。
                NSLog("读取剪贴板快照失败：%@", error.localizedDescription)
                return
            }

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard generation == self.reloadGeneration else { return }
                self.cards = snapshot.cards
                self.totalItems = snapshot.totalItems
                self.totalStorageBytes = snapshot.totalStorageBytes
            }
        }
    }

    private func scheduleReload(delay: TimeInterval = 0.05, ignoreRemoteMaintenance: Bool = false) {
        guard ignoreRemoteMaintenance || !remoteMaintenancePending else { return }

        reloadWorkItem?.cancel()

        let generation = reloadGeneration &+ 1
        reloadGeneration = generation
        let filter = self.filter
        let searchText = self.searchText
        let timeFilter = self.timeFilter
        let customDateFrom = self.customDateFrom
        let customDateTo = self.customDateTo

        let work = DispatchWorkItem { [weak self] in
            self?.reloadCards(
                generation: generation,
                filter: filter,
                searchText: searchText,
                timeFilter: timeFilter,
                customDateFrom: customDateFrom,
                customDateTo: customDateTo
            )
        }
        reloadWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func currentReloadDelay() -> TimeInterval {
        cloudSyncInProgress ? 0.25 : 0.05
    }

    private func fetchItem(id: UUID) -> ClipboardItem? {
        let request = ClipboardItem.fetchRequest()
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try? context.fetch(request).first
    }

    private func bumpItemToFront(_ item: ClipboardItem) {
        let now = Date()
        item.createdAt = now
        item.updatedAt = now
        saveContext()
        scheduleReload(ignoreRemoteMaintenance: true)
    }

    private func saveContext() {
        guard context.hasChanges else { return }
        try? context.save()
    }

    private func scheduleRemoteMaintenance() {
        remoteMaintenancePending = true

        if remoteMaintenanceInFlight {
            remoteMaintenanceQueued = true
            return
        }

        remoteMaintenanceWorkItem?.cancel()

        let work = DispatchWorkItem { [weak self] in
            self?.performRemoteMaintenance()
        }
        remoteMaintenanceWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func performRemoteMaintenance() {
        remoteMaintenanceWorkItem = nil
        guard !remoteMaintenanceInFlight else {
            remoteMaintenanceQueued = true
            return
        }

        remoteMaintenanceInFlight = true

        let backgroundContext = persistence.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext.undoManager = nil
        let thumbnailCache = thumbnailCache

        backgroundContext.perform { [weak self] in
            var didSave = false
            var removedThumbnailKeys: [String] = []

            do {
                removedThumbnailKeys = try ClipboardStorageOperations.deduplicateItemsByContentHash(in: backgroundContext)
                if backgroundContext.hasChanges {
                    try backgroundContext.save()
                    didSave = true
                }
            } catch {
                didSave = false
            }

            removedThumbnailKeys.forEach(thumbnailCache.removeThumbnail(forKey:))

            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.remoteMaintenanceInFlight = false

                if self.remoteMaintenanceQueued {
                    self.remoteMaintenanceQueued = false
                    self.scheduleRemoteMaintenance()
                    return
                }

                self.remoteMaintenancePending = false
                self.scheduleReload(delay: didSave ? 0.02 : 0.1, ignoreRemoteMaintenance: true)
            }
        }
    }

    private func contentHash(kind: ClipboardEntryKind, payload: Data) -> String {
        var input = Data(kind.rawValue.utf8)
        input.append(payload)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}
