import AppKit

enum ClipboardItemType: String {
    case text
    case url
    case image
    case file
    case unknown
}

struct NormalizedClipboardContent {
    let text: String?
    let url: URL?
    let fileURL: URL?
    let imageData: Data?
    let imageSize: NSSize?
    let imagePath: String?
    let sourceTypes: [NSPasteboard.PasteboardType]
    let capturedAt: Date
    let sourceAppName: String?
    let sourceAppBundleId: String?
}

struct ClipboardItem {
    let id: UUID
    let createdAt: Date
    let type: ClipboardItemType
    let previewTitle: String
    let metadata: [String: String]
    let contentHash: String
    let sourceAppName: String?
    let sourceAppBundleId: String?
    let pinned: Bool
}

struct ClipboardEntry {
    let item: ClipboardItem
    let content: NormalizedClipboardContent
}

extension NormalizedClipboardContent {
    func withImage(imageData: Data?, imagePath: String?) -> NormalizedClipboardContent {
        NormalizedClipboardContent(
            text: text,
            url: url,
            fileURL: fileURL,
            imageData: imageData,
            imageSize: imageSize,
            imagePath: imagePath,
            sourceTypes: sourceTypes,
            capturedAt: capturedAt,
            sourceAppName: sourceAppName,
            sourceAppBundleId: sourceAppBundleId
        )
    }
}
