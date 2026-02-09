import CoreData
import Foundation

final class PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentCloudKitContainer
    let cloudSyncEnabled: Bool
    let thumbnailCache: ThumbnailCache

    private init() {
        let model = Self.makeManagedObjectModel()
        let storeURL = Self.makeStoreURL()

        thumbnailCache = ThumbnailCache()

        let userWantsICloud = Self.readICloudPreference()

        if userWantsICloud {
            let cloudContainerIdentifier = Self.defaultCloudContainerIdentifier()
            if let cloudContainer = try? Self.makeContainer(
                managedObjectModel: model,
                storeURL: storeURL,
                cloudKitContainerIdentifier: cloudContainerIdentifier
            ) {
                container = cloudContainer
                cloudSyncEnabled = true
            } else if let localContainer = try? Self.makeContainer(
                managedObjectModel: model,
                storeURL: storeURL,
                cloudKitContainerIdentifier: nil
            ) {
                container = localContainer
                cloudSyncEnabled = false
            } else {
                fatalError("Unable to initialize persistent store")
            }
        } else {
            if let localContainer = try? Self.makeContainer(
                managedObjectModel: model,
                storeURL: storeURL,
                cloudKitContainerIdentifier: nil
            ) {
                container = localContainer
                cloudSyncEnabled = false
            } else {
                fatalError("Unable to initialize persistent store")
            }
        }

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.undoManager = nil
    }

    private static func makeContainer(
        managedObjectModel: NSManagedObjectModel,
        storeURL: URL,
        cloudKitContainerIdentifier: String?
    ) throws -> NSPersistentCloudKitContainer {
        let container = NSPersistentCloudKitContainer(name: "PasteModel", managedObjectModel: managedObjectModel)
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldMigrateStoreAutomatically = true
        description.shouldInferMappingModelAutomatically = true
        description.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
        description.setOption(true as NSNumber, forKey: NSPersistentStoreRemoteChangeNotificationPostOptionKey)

        if let cloudKitContainerIdentifier {
            let cloudOptions = NSPersistentCloudKitContainerOptions(containerIdentifier: cloudKitContainerIdentifier)
            description.cloudKitContainerOptions = cloudOptions
        }

        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        let semaphore = DispatchSemaphore(value: 0)

        container.loadPersistentStores { _, error in
            loadError = error
            semaphore.signal()
        }

        semaphore.wait()

        if let loadError {
            throw loadError
        }

        return container
    }

    private static func makeStoreURL() -> URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let folderName = Bundle.main.bundleIdentifier ?? "Paste"
        let appDirectory = appSupportURL.appendingPathComponent(folderName, isDirectory: true)
        try? fileManager.createDirectory(at: appDirectory, withIntermediateDirectories: true)
        return appDirectory.appendingPathComponent("Paste.sqlite")
    }

    private static func defaultCloudContainerIdentifier() -> String {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.dorado.paste"
        return "iCloud.\(bundleIdentifier)"
    }

    private static func readICloudPreference() -> Bool {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "iCloudSyncEnabled") == nil {
            return true
        }
        return defaults.bool(forKey: "iCloudSyncEnabled")
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()

        entity.name = "ClipboardItem"
        entity.managedObjectClassName = NSStringFromClass(ClipboardItem.self)

        let id = attribute(name: "id", type: .UUIDAttributeType, optional: false)
        let createdAt = attribute(name: "createdAt", type: .dateAttributeType, optional: false)
        let updatedAt = attribute(name: "updatedAt", type: .dateAttributeType, optional: false)
        let kindRaw = attribute(name: "kindRaw", type: .stringAttributeType, optional: false)
        let contentHash = attribute(name: "contentHash", type: .stringAttributeType, optional: false)
        contentHash.isIndexed = true

        let textContent = attribute(name: "textContent", type: .stringAttributeType, optional: true)
        let urlString = attribute(name: "urlString", type: .stringAttributeType, optional: true)

        let imageData = attribute(name: "imageData", type: .binaryDataAttributeType, optional: true)
        imageData.allowsExternalBinaryDataStorage = true

        let sourceAppName = attribute(name: "sourceAppName", type: .stringAttributeType, optional: true)
        let sourceBundleID = attribute(name: "sourceBundleID", type: .stringAttributeType, optional: true)
        let payloadBytes = attribute(name: "payloadBytes", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let thumbnailBytes = attribute(name: "thumbnailBytes", type: .integer64AttributeType, optional: false, defaultValue: 0)
        let thumbnailKey = attribute(name: "thumbnailKey", type: .stringAttributeType, optional: true)

        entity.properties = [
            id,
            createdAt,
            updatedAt,
            kindRaw,
            contentHash,
            textContent,
            urlString,
            imageData,
            sourceAppName,
            sourceBundleID,
            payloadBytes,
            thumbnailBytes,
            thumbnailKey
        ]
        entity.uniquenessConstraints = [["contentHash"]]

        model.entities = [entity]
        return model
    }

    private static func attribute(
        name: String,
        type: NSAttributeType,
        optional: Bool,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = optional
        attribute.defaultValue = defaultValue
        return attribute
    }
}
