import CoreData
import Foundation
import Testing
@testable import Paste

struct PasteTests {
    private func makeInMemoryContext() throws -> NSManagedObjectContext {
        let model = PersistenceController.makeManagedObjectModelForTesting()
        let container = NSPersistentContainer(name: "PasteModel", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }

        if let loadError {
            throw loadError
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.undoManager = nil
        return container.viewContext
    }

    @Test func duplicateTextUpsertMovesNewestItemToFront() throws {
        let context = try makeInMemoryContext()
        let payload = ClipboardPayload(
            kind: .text,
            text: "same text",
            urlString: nil,
            imageData: nil,
            contentHash: "same-hash",
            payloadBytes: 9
        )
        let source = SourceApplicationInfo(name: "Safari", bundleID: "com.apple.Safari")

        _ = try ClipboardStorageOperations.upsertItem(
            payload: payload,
            sourceApp: source,
            at: Date(timeIntervalSince1970: 100),
            in: context
        )
        try context.save()

        _ = try ClipboardStorageOperations.upsertItem(
            payload: payload,
            sourceApp: source,
            at: Date(timeIntervalSince1970: 200),
            in: context
        )
        try context.save()

        let request = ClipboardItem.fetchRequest()
        request.sortDescriptors = [NSSortDescriptor(key: "createdAt", ascending: false)]
        let items = try context.fetch(request)

        #expect(items.count == 1)
        #expect(items.first?.createdAt == Date(timeIntervalSince1970: 200))
        #expect(items.first?.textContent == "same text")
    }

    @Test func remoteDedupKeepsNewestRealSourceItem() throws {
        let context = try makeInMemoryContext()

        makeItem(
            hash: "dup-hash",
            text: "same text",
            sourceName: "Pasteboard",
            bundleID: "system.pasteboard",
            createdAt: Date(timeIntervalSince1970: 150),
            in: context
        )
        makeItem(
            hash: "dup-hash",
            text: "same text",
            sourceName: "Safari",
            bundleID: "com.apple.Safari",
            createdAt: Date(timeIntervalSince1970: 100),
            in: context
        )
        makeItem(
            hash: "dup-hash",
            text: "same text",
            sourceName: "Notes",
            bundleID: "com.apple.Notes",
            createdAt: Date(timeIntervalSince1970: 200),
            in: context
        )
        try context.save()

        _ = try ClipboardStorageOperations.deduplicateItemsByContentHash(in: context)
        try context.save()

        let request = ClipboardItem.fetchRequest()
        let items = try context.fetch(request)

        #expect(items.count == 1)
        #expect(items.first?.sourceBundleID == "com.apple.Notes")
        #expect(items.first?.createdAt == Date(timeIntervalSince1970: 200))
    }

    private func makeSQLiteContainer() throws -> (NSPersistentContainer, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = NSPersistentContainer(
            name: "PasteSnapshotTests",
            managedObjectModel: PersistenceController.makeManagedObjectModelForTesting()
        )
        let description = NSPersistentStoreDescription(url: directory.appendingPathComponent("Paste.sqlite"))
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        return (container, directory)
    }

    private func removeSQLiteContainer(_ container: NSPersistentContainer, directory: URL) throws {
        container.viewContext.reset()
        for store in container.persistentStoreCoordinator.persistentStores {
            try container.persistentStoreCoordinator.remove(store)
        }
        try FileManager.default.removeItem(at: directory)
    }

    @Test func snapshotKeepsDeletedRecordReadableUntilNextReload() throws {
        let (container, directory) = try makeSQLiteContainer()
        defer { try? removeSQLiteContainer(container, directory: directory) }
        let writer = container.viewContext
        let item = makeItem(
            hash: "snapshot", text: "before deletion", sourceName: "Notes",
            bundleID: "com.apple.Notes", createdAt: Date(), in: writer
        )
        try writer.save()
        let objectID = item.objectID
        let expectedID = item.id
        let reader = container.newBackgroundContext()
        defer { reader.performAndWait { reader.reset() } }

        try reader.performAndWait {
            let snapshot = try ClipboardStorageOperations.makeSnapshot(
                in: reader, filter: .all, searchText: "", timeFilter: .all
            )
            #expect(snapshot.cards.map(\.id) == [expectedID])
            #expect(snapshot.totalItems == 1)
            // 主动退回 fault，模拟取到对象后、真正读取属性前发生删除。
            reader.refresh(reader.object(with: objectID), mergeChanges: false)
        }
        writer.delete(item)
        try writer.save()

        reader.performAndWait {
            let oldItem = reader.object(with: objectID)
            #expect(oldItem.value(forKey: "id") as? UUID == expectedID)
            #expect(oldItem.value(forKey: "textContent") as? String == "before deletion")
        }

        let nextReader = container.newBackgroundContext()
        try nextReader.performAndWait {
            defer { nextReader.reset() }
            let snapshot = try ClipboardStorageOperations.makeSnapshot(
                in: nextReader, filter: .all, searchText: "", timeFilter: .all
            )
            #expect(snapshot.cards.isEmpty)
            #expect(snapshot.totalItems == 0)
            #expect(snapshot.totalStorageBytes == 0)
        }
    }

    @Test func snapshotSkipsMissingRequiredValues() throws {
        let (container, directory) = try makeSQLiteContainer()
        defer { try? removeSQLiteContainer(container, directory: directory) }
        let context = container.viewContext
        let valid = makeItem(
            hash: "valid", text: "valid", sourceName: "Notes",
            bundleID: "com.apple.Notes", createdAt: Date(), in: context
        )
        let expectedID = valid.id
        for key in ["id", "createdAt"] {
            let invalid = makeItem(
                hash: key, text: "invalid", sourceName: "Notes",
                bundleID: "com.apple.Notes", createdAt: Date(), in: context
            )
            // 模拟底层缺值，避免为了构造异常记录破坏持久化模型。
            invalid.setValue(nil, forKey: key)
        }
        let snapshot = try ClipboardStorageOperations.makeSnapshot(
            in: context, filter: .all, searchText: "", timeFilter: .all
        )
        #expect(snapshot.cards.map(\.id) == [expectedID])
        #expect(snapshot.cards.first?.previewText == "valid")
    }

    @Test func snapshotPreservesFiltersAndGlobalTotals() throws {
        let (container, directory) = try makeSQLiteContainer()
        defer { try? removeSQLiteContainer(container, directory: directory) }
        let context = container.viewContext
        let favorite = makeItem(
            hash: "favorite", text: "keep", sourceName: "Notes",
            bundleID: "com.apple.Notes", createdAt: Date(timeIntervalSince1970: 200), in: context
        )
        favorite.isFavorite = true
        makeItem(
            hash: "other", text: "other", sourceName: "Notes",
            bundleID: "com.apple.Notes", createdAt: Date(timeIntervalSince1970: 100), in: context
        )
        try context.save()
        let expectedID = favorite.id
        let reader = container.newBackgroundContext()
        try reader.performAndWait {
            defer { reader.reset() }
            let snapshot = try ClipboardStorageOperations.makeSnapshot(
                in: reader, filter: .favorites, searchText: "keep", timeFilter: .customRange,
                customDateFrom: Date(timeIntervalSince1970: 0),
                customDateTo: Date(timeIntervalSince1970: 300)
            )
            #expect(snapshot.cards.map(\.id) == [expectedID])
            #expect(snapshot.cards.first?.isFavorite == true)
            #expect(snapshot.totalItems == 2)
            #expect(snapshot.totalStorageBytes == 9)
        }
    }

    @discardableResult
    private func makeItem(
        hash: String,
        text: String,
        sourceName: String,
        bundleID: String,
        createdAt: Date,
        in context: NSManagedObjectContext
    ) -> ClipboardItem {
        let item = ClipboardItem(context: context)
        item.id = UUID()
        item.createdAt = createdAt
        item.updatedAt = createdAt
        item.kind = .text
        item.contentHash = hash
        item.textContent = text
        item.urlString = nil
        item.imageData = nil
        item.sourceAppName = sourceName
        item.sourceBundleID = bundleID
        item.payloadBytes = Int64(text.utf8.count)
        item.thumbnailBytes = 0
        item.thumbnailKey = nil
        item.isFavorite = false
        return item
    }
}
