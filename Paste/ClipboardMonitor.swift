import AppKit
import CryptoKit
import Foundation

struct ClipboardPayload {
    let kind: ClipboardEntryKind
    let text: String?
    let urlString: String?
    let imageData: Data?
    let contentHash: String
    let payloadBytes: Int64
}

struct SourceApplicationInfo {
    let name: String
    let bundleID: String
}

@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private var timer: Timer?
    private var lastChangeCount: Int
    private var skippedChanges = 0

    private let pollInterval: TimeInterval
    private let onCapture: (ClipboardPayload, SourceApplicationInfo) -> Void

    init(
        pollInterval: TimeInterval = 0.7,
        onCapture: @escaping (ClipboardPayload, SourceApplicationInfo) -> Void
    ) {
        self.pollInterval = pollInterval
        self.onCapture = onCapture
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        guard timer == nil else { return }

        let timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollPasteboard()
        }
        timer.tolerance = 0.2
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func skipNextCapture() {
        skippedChanges += 1
    }

    private func pollPasteboard() {
        let currentCount = pasteboard.changeCount
        guard currentCount != lastChangeCount else {
            return
        }
        lastChangeCount = currentCount

        if skippedChanges > 0 {
            skippedChanges -= 1
            return
        }

        guard let payload = readPayload() else {
            return
        }

        onCapture(payload, currentSourceApp())
    }

    private func readPayload() -> ClipboardPayload? {
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

        if
            let urlObjects = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL],
            let url = urlObjects.first
        {
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
            let text = pasteboard.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        {
            if let url = URL(string: text), url.scheme != nil {
                return ClipboardPayload(
                    kind: .url,
                    text: nil,
                    urlString: url.absoluteString,
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

    private func currentSourceApp() -> SourceApplicationInfo {
        let frontApp = NSWorkspace.shared.frontmostApplication
        return SourceApplicationInfo(
            name: frontApp?.localizedName ?? "Unknown",
            bundleID: frontApp?.bundleIdentifier ?? "unknown.bundle"
        )
    }

    private func contentHash(kind: ClipboardEntryKind, payload: Data) -> String {
        var input = Data(kind.rawValue.utf8)
        input.append(payload)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }
}
