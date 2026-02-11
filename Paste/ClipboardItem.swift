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
    case favorites
    case text
    case url
    case image

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all:
            return "All"
        case .favorites:
            return "Favorites"
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
        case .all, .favorites:
            return nil
        case .text:
            return .text
        case .url:
            return .url
        case .image:
            return .image
        }
    }

    var isFavoritesFilter: Bool {
        self == .favorites
    }

    func localizedTitle(_ l: L) -> String {
        switch self {
        case .all: return l.filterAll
        case .favorites: return l.filterFavorites
        case .text: return l.filterText
        case .url: return l.filterURL
        case .image: return l.filterImage
        }
    }
}

enum TimeFilter: String, CaseIterable, Identifiable {
    case all
    case today
    case sevenDays
    case thirtyDays

    var id: String { rawValue }

    /// 返回筛选起始日期，nil 表示不限
    var startDate: Date? {
        let cal = Calendar.current
        let now = Date()
        switch self {
        case .all:
            return nil
        case .today:
            return cal.startOfDay(for: now)
        case .sevenDays:
            return cal.date(byAdding: .day, value: -7, to: now)
        case .thirtyDays:
            return cal.date(byAdding: .day, value: -30, to: now)
        }
    }

    func localizedTitle(_ l: L) -> String {
        switch self {
        case .all: return l.timeFilterAll
        case .today: return l.timeFilterToday
        case .sevenDays: return l.timeFilter7Days
        case .thirtyDays: return l.timeFilter30Days
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
    @NSManaged public var isFavorite: Bool
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
    let isFavorite: Bool

    // 内容元信息
    let characterCount: Int
    let imageWidth: Int?
    let imageHeight: Int?

    // 智能内容识别
    let smartContentType: SmartContentType
}
