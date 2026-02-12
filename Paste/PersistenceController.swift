import CloudKit
import CoreData
import Foundation
import os

final class PersistenceController {
    static let shared = PersistenceController()
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Paste", category: "CloudSync")

    let container: NSPersistentCloudKitContainer
    let cloudSyncEnabled: Bool
    let cloudSyncErrorMessage: String?
    let thumbnailCache: ThumbnailCache

    private init() {
        let model = Self.makeManagedObjectModel()
        let storeURL = Self.makeStoreURL()

        thumbnailCache = ThumbnailCache()

        let userWantsICloud = Self.readICloudPreference()

        let resolvedContainer: NSPersistentCloudKitContainer
        let resolvedCloudSyncEnabled: Bool
        let resolvedCloudSyncErrorMessage: String?

        if userWantsICloud {
            let cloudContainerIdentifier = Self.defaultCloudContainerIdentifier()
            do {
                resolvedContainer = try Self.makeContainer(
                    managedObjectModel: model,
                    storeURL: storeURL,
                    cloudKitContainerIdentifier: cloudContainerIdentifier
                )
                resolvedCloudSyncEnabled = true
                resolvedCloudSyncErrorMessage = nil
            } catch {
                let errorMessage = Self.describeCloudKitError(
                    error,
                    containerIdentifier: cloudContainerIdentifier
                )
                Self.logger.error("CloudKit store load failed. \(errorMessage, privacy: .public)")
                resolvedCloudSyncErrorMessage = errorMessage

                if let localContainer = try? Self.makeContainer(
                    managedObjectModel: model,
                    storeURL: storeURL,
                    cloudKitContainerIdentifier: nil
                ) {
                    resolvedContainer = localContainer
                    resolvedCloudSyncEnabled = false
                } else {
                    fatalError("Unable to initialize persistent store")
                }
            }
        } else {
            if let localContainer = try? Self.makeContainer(
                managedObjectModel: model,
                storeURL: storeURL,
                cloudKitContainerIdentifier: nil
            ) {
                resolvedContainer = localContainer
                resolvedCloudSyncEnabled = false
                resolvedCloudSyncErrorMessage = nil
            } else {
                fatalError("Unable to initialize persistent store")
            }
        }

        container = resolvedContainer
        cloudSyncEnabled = resolvedCloudSyncEnabled
        cloudSyncErrorMessage = resolvedCloudSyncErrorMessage

        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        container.viewContext.automaticallyMergesChangesFromParent = true
        container.viewContext.undoManager = nil

        // 打印 iCloud 同步状态
        logCloudSyncStatus()

        registerCloudKitEventObserverIfNeeded()
    }

    private func logCloudSyncStatus() {
        let userWantsICloud = Self.readICloudPreference()
        Self.logger.info("========== iCloud 同步状态 ==========")
        Self.logger.info("用户设置 iCloud 同步: \(userWantsICloud ? "开启" : "关闭")")
        Self.logger.info("实际 iCloud 同步状态: \(self.cloudSyncEnabled ? "✅ 已启用" : "❌ 未启用")")

        if let errorMessage = cloudSyncErrorMessage {
            Self.logger.error("iCloud 同步错误: \(errorMessage, privacy: .public)")
        }

        // 检查 CloudKit 容器配置
        let containerIdentifier = Self.defaultCloudContainerIdentifier()
        Self.logger.info("CloudKit 容器 ID: \(containerIdentifier)")

        // ubiquityIdentityToken 为 nil 表示 iCloud 不可用
        // （未登录、受限或应用缺少签名权限），此时不能调用 CKContainer API，否则会 SIGTRAP 崩溃
        guard FileManager.default.ubiquityIdentityToken != nil else {
            Self.logger.info("iCloud 账户状态: ❌ iCloud 不可用（未登录或应用缺少签名权限）")
            Self.logger.info("=====================================")
            return
        }

        // 检查 iCloud 账户状态
        Task {
            await self.checkCloudKitAccountStatus()
        }
    }

    private func checkCloudKitAccountStatus() async {
        do {
            let status = try await CKContainer(identifier: Self.defaultCloudContainerIdentifier()).accountStatus()
            let statusString: String
            switch status {
            case .available:
                statusString = "✅ 可用"
            case .noAccount:
                statusString = "❌ 未登录 iCloud 账户"
            case .restricted:
                statusString = "⚠️ 受限（家长控制）"
            case .couldNotDetermine:
                statusString = "⚠️ 无法确定状态"
            case .temporarilyUnavailable:
                statusString = "⚠️ 暂时不可用"
            @unknown default:
                statusString = "⚠️ 未知状态"
            }
            Self.logger.info("iCloud 账户状态: \(statusString)")
            Self.logger.info("=====================================")
        } catch {
            Self.logger.error("检查 iCloud 账户状态失败: \(error.localizedDescription, privacy: .public)")
        }
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

    private static func describeCloudKitError(_ error: Error, containerIdentifier: String) -> String {
        let nsError = error as NSError
        var parts: [String] = [
            "Container \(containerIdentifier)",
            "\(nsError.domain)(\(nsError.code))",
            nsError.localizedDescription
        ]
        if let reason = nsError.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !reason.isEmpty {
            parts.append(reason)
        }
        return parts.joined(separator: " - ")
    }

    private func registerCloudKitEventObserverIfNeeded() {
        guard cloudSyncEnabled else { return }
        _ = NotificationCenter.default.addObserver(
            forName: NSPersistentCloudKitContainer.eventChangedNotification,
            object: container,
            queue: .main
        ) { notification in
            guard
                let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                    as? NSPersistentCloudKitContainer.Event
            else {
                return
            }

            if let error = event.error {
                Self.logger.error("CloudKit event error: \(error, privacy: .public)")
            }
        }
    }

    /// 处理远程推送通知
    /// NSPersistentCloudKitContainer 会自动处理 CloudKit 同步，
    /// 此方法仅用于通知 Core Data 有远程变更可用
    func handleRemoteNotification(_ userInfo: [AnyHashable: Any]) -> Bool {
        guard cloudSyncEnabled else { return false }

        // 检查是否为 CloudKit 数据库变更通知
        guard let ck = userInfo["ck"] as? [String: Any],
              userInfo["aps"] != nil
        else {
            Self.logger.debug("通知不包含 CloudKit 变更信息")
            return false
        }

        Self.logger.info("收到 CloudKit 远程变更通知: \(String(describing: ck.keys))")

        // NSPersistentCloudKitContainer 会自动监听远程变更并同步
        // 收到推送通知后，我们只需确保 viewContext 刷新即可
        container.viewContext.refreshAllObjects()

        return true
    }

    private static func makeManagedObjectModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let entity = NSEntityDescription()

        entity.name = "ClipboardItem"
        entity.managedObjectClassName = NSStringFromClass(ClipboardItem.self)

        // CloudKit 要求：所有非可选属性必须有默认值
        let id = attribute(name: "id", type: .UUIDAttributeType, optional: false, defaultValue: UUID())
        let createdAt = attribute(name: "createdAt", type: .dateAttributeType, optional: false, defaultValue: Date())
        let updatedAt = attribute(name: "updatedAt", type: .dateAttributeType, optional: false, defaultValue: Date())
        let kindRaw = attribute(name: "kindRaw", type: .stringAttributeType, optional: false, defaultValue: "text")
        let contentHash = attribute(name: "contentHash", type: .stringAttributeType, optional: false, defaultValue: "")
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
        let isFavorite = attribute(name: "isFavorite", type: .booleanAttributeType, optional: false, defaultValue: false)

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
            thumbnailKey,
            isFavorite
        ]
        // CloudKit 不支持唯一约束，改用代码层面去重
        // entity.uniquenessConstraints = [["contentHash"]]

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
