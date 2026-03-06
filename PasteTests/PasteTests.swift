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
