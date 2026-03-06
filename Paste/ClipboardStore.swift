import Combine
import CoreData
import CryptoKit
import Foundation
import ImageIO
#if os(macOS)
import AppKit
#elseif os(iOS)
import UIKit
#endif

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
            let keeper: ClipboardItem
            if let realSource = items.first(where: isRealSource(_:)) {
                keeper = realSource
            } else {
                keeper = items[0]
            }

            for item in items where item !== keeper {
                if let key = item.thumbnailKey {
                    removedThumbnailKeys.append(key)
                }
                context.delete(item)
            }
        }

        return removedThumbnailKeys
    }

    nonisolated static func makeSnapshot(
        in context: NSManagedObjectContext,
        filter: ClipboardFilter,
        searchText: String,
        timeFilter: TimeFilter
    ) -> ClipboardSnapshot {
        let request = makeCardsRequest(
            filter: filter,
            searchText: searchText,
            timeFilter: timeFilter
        )

        guard let fetched = try? context.fetch(request) else {
            return ClipboardSnapshot(cards: [], totalItems: 0, totalStorageBytes: 0)
        }

        let cards = fetched.map { item in
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
        let totals = (try? context.fetch(totalsRequest)) ?? []

        return ClipboardSnapshot(
            cards: cards,
            totalItems: totals.count,
            totalStorageBytes: totals.reduce(0) { $0 + $1.storageBytes }
        )
    }

    nonisolated private static func makeCardsRequest(
        filter: ClipboardFilter,
        searchText: String,
        timeFilter: TimeFilter
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

        if let startDate = timeFilter.startDate {
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
    #if os(macOS)
    private var remoteMaintenanceWorkItem: DispatchWorkItem?
    private var remoteMaintenancePending = false
    private var remoteMaintenanceInFlight = false
    private var remoteMaintenanceQueued = false
    #endif
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
        scheduleReload(delay: 0, ignoreRemoteMaintenance: true)
        #if os(macOS)
        if cloudSyncEnabled {
            scheduleRemoteMaintenance()
        }
        #endif
    }

    deinit {
        let center = NotificationCenter.default
        observers.forEach(center.removeObserver)
        reloadWorkItem?.cancel()
        #if os(macOS)
        remoteMaintenanceWorkItem?.cancel()
        #endif
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
        scheduleReload(ignoreRemoteMaintenance: true)
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

    func clearAll() {
        let request = ClipboardItem.fetchRequest()
        guard let allItems = try? context.fetch(request) else { return }

        allItems.forEach { item in
            thumbnailCache.removeThumbnail(forKey: item.thumbnailKey)
            context.delete(item)
        }

        saveContext()
        scheduleReload(ignoreRemoteMaintenance: true)
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
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                #if os(macOS)
                guard !self.remoteMaintenancePending else { return }
                #endif
                self.scheduleReload(delay: self.currentReloadDelay())
            }
        }

        let remoteObserver = center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: nil
        ) { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                #if os(macOS)
                self?.scheduleRemoteMaintenance()
                #else
                self?.scheduleReload(delay: 0.2)
                #endif
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

        // 如果同内容已存在（无论来自 iCloud 同步还是本地），跳过不重复创建
        let existingRequest = ClipboardItem.fetchRequest()
        existingRequest.predicate = NSPredicate(format: "contentHash == %@", payload.contentHash)
        if let existingItems = try? context.fetch(existingRequest), !existingItems.isEmpty {
            return false
        }

        if cloudSyncEnabled {
            // iCloud 同步启用时，延迟创建以等待 CloudKit 同步 Mac 端的真实条目
            // Universal Clipboard 比 CloudKit 快得多，直接创建会导致来源显示为 "iOS Clipboard"
            let hash = payload.contentHash
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                guard let self else { return }
                let check = ClipboardItem.fetchRequest()
                check.predicate = NSPredicate(format: "contentHash == %@", hash)
                if let existing = try? self.context.fetch(check), !existing.isEmpty {
                    return // CloudKit 已同步真实条目，跳过本地创建
                }
                let source = SourceApplicationInfo(
                    name: "iOS Clipboard",
                    bundleID: "system.pasteboard"
                )
                self.save(payload: payload, sourceApp: source, playFeedback: false)
            }
        } else {
            let source = SourceApplicationInfo(
                name: "iOS Clipboard",
                bundleID: "system.pasteboard"
            )
            save(payload: payload, sourceApp: source, playFeedback: false)
        }
        return true
    }
    #endif

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

    private func reloadCards(
        generation: UInt64,
        filter: ClipboardFilter,
        searchText: String,
        timeFilter: TimeFilter
    ) {
        let backgroundContext = persistence.container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext.undoManager = nil

        backgroundContext.perform { [weak self] in
            let snapshot = ClipboardStorageOperations.makeSnapshot(
                in: backgroundContext,
                filter: filter,
                searchText: searchText,
                timeFilter: timeFilter
            )

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
        #if os(macOS)
        guard ignoreRemoteMaintenance || !remoteMaintenancePending else { return }
        #endif

        reloadWorkItem?.cancel()

        let generation = reloadGeneration &+ 1
        reloadGeneration = generation
        let filter = self.filter
        let searchText = self.searchText
        let timeFilter = self.timeFilter

        let work = DispatchWorkItem { [weak self] in
            self?.reloadCards(
                generation: generation,
                filter: filter,
                searchText: searchText,
                timeFilter: timeFilter
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

    #if os(macOS)
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
    #endif

    private func contentHash(kind: ClipboardEntryKind, payload: Data) -> String {
        var input = Data(kind.rawValue.utf8)
        input.append(payload)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}
