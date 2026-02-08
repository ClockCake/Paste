import AppKit
import Combine
import CoreData
import Foundation

@MainActor
final class ClipboardStore: ObservableObject {
    @Published var filter: ClipboardFilter = .all {
        didSet {
            reloadCards()
        }
    }

    @Published private(set) var cards: [ClipboardCard] = []
    @Published private(set) var totalItems: Int = 0
    @Published private(set) var totalStorageBytes: Int64 = 0

    let cloudSyncEnabled: Bool

    private let maxItems = 500
    private let maxStorageBytes: Int64 = 512 * 1024 * 1024

    private let persistence: PersistenceController
    private let context: NSManagedObjectContext
    private let thumbnailCache: ThumbnailCache

    private var monitor: ClipboardMonitor?
    private var observers: [NSObjectProtocol] = []
    private var started = false

    init(persistence: PersistenceController) {
        self.persistence = persistence
        context = persistence.container.viewContext
        thumbnailCache = persistence.thumbnailCache
        cloudSyncEnabled = persistence.cloudSyncEnabled

        registerObservers()
        reloadCards()
    }

    var storageText: String {
        ByteCountFormatter.string(fromByteCount: totalStorageBytes, countStyle: .file)
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
        thumbnailCache.image(forKey: key)
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
        reloadCards()
    }

    func clearAll() {
        let request = ClipboardItem.fetchRequest()
        guard let allItems = try? context.fetch(request) else { return }

        allItems.forEach { item in
            thumbnailCache.removeThumbnail(forKey: item.thumbnailKey)
            context.delete(item)
        }

        saveContext()
        reloadCards()
    }

    private func registerObservers() {
        let center = NotificationCenter.default

        let contextObserver = center.addObserver(
            forName: .NSManagedObjectContextObjectsDidChange,
            object: context,
            queue: .main
        ) { [weak self] _ in
            self?.reloadCards()
        }

        let remoteObserver = center.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: persistence.container.persistentStoreCoordinator,
            queue: .main
        ) { [weak self] _ in
            self?.reloadCards()
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
        reloadCards()
    }

    private func pruneIfNeeded() {
        let request = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: true)]

        guard let allItems = try? context.fetch(request) else {
            return
        }

        var currentCount = allItems.count
        var currentBytes = allItems.reduce(0) { $0 + $1.storageBytes }
        var didDelete = false

        for item in allItems where currentCount > maxItems || currentBytes > maxStorageBytes {
            currentCount -= 1
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

        if let kind = filter.kind {
            request.predicate = NSPredicate(format: "kindRaw == %@", kind.rawValue)
        }

        guard let fetched = try? context.fetch(request) else {
            cards = []
            totalItems = 0
            totalStorageBytes = 0
            return
        }

        cards = fetched.map {
            ClipboardCard(
                id: $0.id,
                kind: $0.kind,
                createdAt: $0.createdAt,
                sourceAppName: $0.sourceAppName ?? "Unknown",
                sourceBundleID: $0.sourceBundleID ?? "unknown.bundle",
                previewText: $0.previewText,
                thumbnailKey: $0.thumbnailKey
            )
        }

        let totalsRequest = ClipboardItem.fetchRequest()
        if let allItems = try? context.fetch(totalsRequest) {
            totalItems = allItems.count
            totalStorageBytes = allItems.reduce(0) { $0 + $1.storageBytes }
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
