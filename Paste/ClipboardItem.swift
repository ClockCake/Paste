import CoreData
import Foundation

enum ClipboardEntryKind: String, CaseIterable {
    case text
    case url
    case image

    var title: String {
        switch self {
        case .text:
            return "Text"
        case .url:
            return "URL"
        case .image:
            return "Image"
        }
    }

    var symbolName: String {
        switch self {
        case .text:
            return "text.alignleft"
        case .url:
            return "link"
        case .image:
            return "photo"
        }
    }

    func localizedTitle(_ l: L) -> String {
        switch self {
        case .text: return l.kindText
        case .url: return l.kindURL
        case .image: return l.kindImage
        }
    }
}

enum ClipboardFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case url
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .text:
            return "Text"
        case .url:
            return "URL"
        case .image:
            return "Image"
        }
    }

    var kind: ClipboardEntryKind? {
        switch self {
        case .all:
            return nil
        case .text:
            return .text
        case .url:
            return .url
        case .image:
            return .image
        }
    }

    func localizedTitle(_ l: L) -> String {
        switch self {
        case .all: return l.filterAll
        case .text: return l.filterText
        case .url: return l.filterURL
        case .image: return l.filterImage
        }
    }
}

@objc(ClipboardItem)
public final class ClipboardItem: NSManagedObject {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<ClipboardItem> {
        NSFetchRequest<ClipboardItem>(entityName: "ClipboardItem")
    }

    @NSManaged public var id: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var kindRaw: String
    @NSManaged public var contentHash: String
    @NSManaged public var textContent: String?
    @NSManaged public var urlString: String?
    @NSManaged public var imageData: Data?
    @NSManaged public var sourceAppName: String?
    @NSManaged public var sourceBundleID: String?
    @NSManaged public var payloadBytes: Int64
    @NSManaged public var thumbnailBytes: Int64
    @NSManaged public var thumbnailKey: String?
}

extension ClipboardItem: Identifiable {}

extension ClipboardItem {
    var kind: ClipboardEntryKind {
        get { ClipboardEntryKind(rawValue: kindRaw) ?? .text }
        set { kindRaw = newValue.rawValue }
    }

    var previewText: String {
        switch kind {
        case .text:
            return textContent ?? ""
        case .url:
            return urlString ?? ""
        case .image:
            return "Image"
        }
    }

    var storageBytes: Int64 {
        payloadBytes + thumbnailBytes
    }
}

struct ClipboardCard: Identifiable {
    let id: UUID
    let kind: ClipboardEntryKind
    let createdAt: Date
    let sourceAppName: String
    let sourceBundleID: String
    let previewText: String
    let thumbnailKey: String?
}
