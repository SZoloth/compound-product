import AppKit
import ImageIO

final class ClipboardNormalizer {
    func normalize(
        items: [NSPasteboardItem],
        capturedAt: Date,
        sourceAppName: String?,
        sourceAppBundleId: String?
    ) -> [NormalizedClipboardContent] {
        items.map { item in
            let types = item.types
            let text = item.string(forType: .string)
                ?? item.string(forType: NSPasteboard.PasteboardType("public.utf8-plain-text"))
            let urlString = item.string(forType: NSPasteboard.PasteboardType("public.url"))
            let url = urlString.flatMap { URL(string: $0) }

            let fileURLString = item.string(forType: .fileURL)
            let fileURL = fileURLString.flatMap { URL(string: $0) }

            let imageData = item.data(forType: .png) ?? item.data(forType: .tiff)
            let imageSize: NSSize? = imageData.flatMap { imageDimensions(from: $0) }

            return NormalizedClipboardContent(
                text: text,
                url: url,
                fileURL: fileURL,
                imageData: imageData,
                imageSize: imageSize,
                imagePath: nil,
                sourceTypes: types,
                capturedAt: capturedAt,
                sourceAppName: sourceAppName,
                sourceAppBundleId: sourceAppBundleId
            )
        }
    }

    private func imageDimensions(from data: Data) -> NSSize? {
        let options: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        guard let width = properties[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = properties[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }
        return NSSize(width: width, height: height)
    }
}
