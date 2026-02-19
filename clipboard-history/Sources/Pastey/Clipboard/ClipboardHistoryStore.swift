import Foundation

extension Notification.Name {
    static let clipboardHistoryDidUpdate = Notification.Name("clipboardHistoryDidUpdate")
}

@MainActor
final class ClipboardHistoryStore {
    private(set) var entries: [ClipboardEntry] = []
    private var retentionLimit: Int
    private let persistence: ClipboardPersistence?
    private var recentHashes: [String: Date] = [:]
    private let dedupeWindow: TimeInterval = 2.0

    init(retentionLimit: Int = 200, persistence: ClipboardPersistence? = nil) {
        self.retentionLimit = retentionLimit
        self.persistence = persistence
        if let stored = persistence?.loadEntries() {
            entries = stored
        }
    }

    func add(_ newEntries: [ClipboardEntry]) {
        let filtered = newEntries.filter { shouldAccept($0) }
        guard !filtered.isEmpty else { return }
        let savedPaths = persistence?.save(entries: filtered) ?? [:]
        let memoryEntries = filtered.map { entry in
            if let path = savedPaths[entry.item.id] {
                let content = entry.content.withImage(imageData: nil, imagePath: path)
                return ClipboardEntry(item: entry.item, content: content)
            }
            return entry
        }
        entries.insert(contentsOf: memoryEntries, at: 0)
        trimToLimit()
        NotificationCenter.default.post(name: .clipboardHistoryDidUpdate, object: self)
    }

    func delete(id: UUID) {
        entries.removeAll { $0.item.id == id }
        persistence?.delete(id: id)
        NotificationCenter.default.post(name: .clipboardHistoryDidUpdate, object: self)
    }

    func updateRetentionLimit(_ limit: Int) {
        retentionLimit = limit
        trimToLimit()
        NotificationCenter.default.post(name: .clipboardHistoryDidUpdate, object: self)
    }

    func togglePinned(id: UUID) {
        guard let index = entries.firstIndex(where: { $0.item.id == id }) else { return }
        let entry = entries[index]
        let updatedItem = ClipboardItem(
            id: entry.item.id,
            createdAt: entry.item.createdAt,
            type: entry.item.type,
            previewTitle: entry.item.previewTitle,
            metadata: entry.item.metadata,
            contentHash: entry.item.contentHash,
            sourceAppName: entry.item.sourceAppName,
            sourceAppBundleId: entry.item.sourceAppBundleId,
            pinned: !entry.item.pinned
        )
        let updatedEntry = ClipboardEntry(item: updatedItem, content: entry.content)
        entries[index] = updatedEntry
        persistence?.updatePinned(id: id, pinned: updatedItem.pinned)
        NotificationCenter.default.post(name: .clipboardHistoryDidUpdate, object: self)
    }

    private func trimToLimit() {
        guard entries.count > retentionLimit else { return }
        var idsToDelete: [UUID] = []
        var index = entries.count - 1
        while entries.count - idsToDelete.count > retentionLimit && index >= 0 {
            if !entries[index].item.pinned {
                idsToDelete.append(entries[index].item.id)
            }
            index -= 1
        }
        if entries.count - idsToDelete.count > retentionLimit {
            index = entries.count - 1
            while entries.count - idsToDelete.count > retentionLimit && index >= 0 {
                idsToDelete.append(entries[index].item.id)
                index -= 1
            }
        }
        if !idsToDelete.isEmpty {
            let deleteSet = Set(idsToDelete)
            entries.removeAll { deleteSet.contains($0.item.id) }
            persistence?.delete(ids: idsToDelete)
        }
    }

    func entry(at index: Int) -> ClipboardEntry? {
        guard entries.indices.contains(index) else { return nil }
        return entries[index]
    }

    func entry(id: UUID) -> ClipboardEntry? {
        entries.first { $0.item.id == id }
    }

    var latestEntry: ClipboardEntry? {
        entries.first
    }

    func search(query: String?, type: ClipboardItemType?, pinnedOnly: Bool, limit: Int) -> [ClipboardEntry] {
        let term = query?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let maxLimit = max(1, min(limit, 200))
        return entries.filter { entry in
            if pinnedOnly && !entry.item.pinned { return false }
            if let type, entry.item.type != type { return false }
            if let term, !term.isEmpty {
                let values = [
                    entry.item.previewTitle,
                    entry.content.text ?? "",
                    entry.content.url?.absoluteString ?? "",
                    entry.content.fileURL?.path ?? "",
                    entry.item.sourceAppName ?? ""
                ].map { $0.lowercased() }
                return values.contains(where: { $0.contains(term) })
            }
            return true
        }.prefix(maxLimit).map { $0 }
    }

    private func shouldAccept(_ entry: ClipboardEntry) -> Bool {
        let now = entry.item.createdAt
        if let last = recentHashes[entry.item.contentHash], now.timeIntervalSince(last) < dedupeWindow {
            return false
        }
        recentHashes[entry.item.contentHash] = now
        return true
    }
}
