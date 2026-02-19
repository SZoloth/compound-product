import AppKit
import CryptoKit

final class ClipboardClassifier {
    func classify(_ normalized: NormalizedClipboardContent) -> ClipboardItem {
        let contentHash = hashContent(normalized)
        let createdAt = normalized.capturedAt

        if let imageSize = normalized.imageSize {
            let title = "Image (\(Int(imageSize.width))x\(Int(imageSize.height)))"
            return ClipboardItem(
                id: UUID(),
                createdAt: createdAt,
                type: .image,
                previewTitle: title,
                metadata: [
                    "width": "\(Int(imageSize.width))",
                    "height": "\(Int(imageSize.height))"
                ],
                contentHash: contentHash,
                sourceAppName: normalized.sourceAppName,
                sourceAppBundleId: normalized.sourceAppBundleId,
                pinned: false
            )
        }

        if let fileURL = normalized.fileURL {
            return ClipboardItem(
                id: UUID(),
                createdAt: createdAt,
                type: .file,
                previewTitle: fileURL.path,
                metadata: ["path": fileURL.path],
                contentHash: contentHash,
                sourceAppName: normalized.sourceAppName,
                sourceAppBundleId: normalized.sourceAppBundleId,
                pinned: false
            )
        }

        if let url = normalized.url ?? normalized.text.flatMap({ URL(string: $0) }), url.scheme != nil {
            return ClipboardItem(
                id: UUID(),
                createdAt: createdAt,
                type: .url,
                previewTitle: url.absoluteString,
                metadata: ["url": url.absoluteString],
                contentHash: contentHash,
                sourceAppName: normalized.sourceAppName,
                sourceAppBundleId: normalized.sourceAppBundleId,
                pinned: false
            )
        }

        if let text = normalized.text, !text.isEmpty {
            let preview = truncate(text, limit: 140)
            return ClipboardItem(
                id: UUID(),
                createdAt: createdAt,
                type: .text,
                previewTitle: preview,
                metadata: [:],
                contentHash: contentHash,
                sourceAppName: normalized.sourceAppName,
                sourceAppBundleId: normalized.sourceAppBundleId,
                pinned: false
            )
        }

        return ClipboardItem(
            id: UUID(),
            createdAt: createdAt,
            type: .unknown,
            previewTitle: "Unknown clipboard item",
            metadata: ["types": normalized.sourceTypes.map { $0.rawValue }.joined(separator: ", ")],
            contentHash: contentHash,
            sourceAppName: normalized.sourceAppName,
            sourceAppBundleId: normalized.sourceAppBundleId,
            pinned: false
        )
    }

    private func truncate(_ text: String, limit: Int) -> String {
        if text.count <= limit { return text }
        let index = text.index(text.startIndex, offsetBy: limit)
        return String(text[..<index]) + "…"
    }

    private func hashContent(_ normalized: NormalizedClipboardContent) -> String {
        var hasher = SHA256()
        if let data = normalized.imageData {
            hasher.update(data: data)
        } else if let text = normalized.text {
            hasher.update(data: Data(text.utf8))
        } else if let url = normalized.url {
            hasher.update(data: Data(url.absoluteString.utf8))
        } else if let fileURL = normalized.fileURL {
            hasher.update(data: Data(fileURL.path.utf8))
        } else {
            let types = normalized.sourceTypes.map { $0.rawValue }.joined(separator: "|")
            hasher.update(data: Data(types.utf8))
        }
        let digest = hasher.finalize()
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
