import AppKit
import Foundation
import SQLite3

@MainActor
final class ClipboardPersistence {
    private let dbURL: URL
    private let imagesURL: URL
    private var db: OpaquePointer?
    private let encryptionKey: String
    private var encryptionEnabled = false

    init() {
        let fm = FileManager.default
        let baseURL = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let appSupport = baseURL.appendingPathComponent("Pastey", isDirectory: true)
        let imagesDir = appSupport.appendingPathComponent("Images", isDirectory: true)
        self.dbURL = appSupport.appendingPathComponent("clipboard.sqlite")
        self.imagesURL = imagesDir
        self.encryptionKey = KeychainHelper.shared.fetchOrCreateKey()

        try? fm.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try? fm.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        openDatabase()
        createTables()
        migrateIfNeeded()
    }

    func loadEntries() -> [ClipboardEntry] {
        let sql = """
        SELECT id, created_at, type, preview_title, content_hash, text, url, file_path, image_path, image_width, image_height, source_app_name, source_app_bundle_id, pinned
        FROM entries
        ORDER BY pinned DESC, created_at DESC;
        """
        var stmt: OpaquePointer?
        var results: [ClipboardEntry] = []
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return results }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let idString = columnText(stmt, index: 0) else { continue }
            let createdAt = Date(timeIntervalSince1970: sqlite3_column_double(stmt, 1))
            let typeString = columnText(stmt, index: 2) ?? ClipboardItemType.unknown.rawValue
            let previewTitle = columnText(stmt, index: 3) ?? ""
            let contentHash = columnText(stmt, index: 4) ?? ""
            let text = columnText(stmt, index: 5)
            let urlString = columnText(stmt, index: 6)
            let filePath = columnText(stmt, index: 7)
            let imagePath = columnText(stmt, index: 8)
            let width = sqlite3_column_int(stmt, 9)
            let height = sqlite3_column_int(stmt, 10)
            let sourceAppName = columnText(stmt, index: 11)
            let sourceAppBundleId = columnText(stmt, index: 12)
            let pinned = sqlite3_column_int(stmt, 13) == 1

            let id = UUID(uuidString: idString) ?? UUID()
            let type = ClipboardItemType(rawValue: typeString) ?? .unknown
            let url = urlString.flatMap { URL(string: $0) }
            let fileURL = filePath.flatMap { URL(fileURLWithPath: $0) }
            let imageSize: NSSize? = (width > 0 && height > 0) ? NSSize(width: CGFloat(width), height: CGFloat(height)) : nil

            let content = NormalizedClipboardContent(
                text: text,
                url: url,
                fileURL: fileURL,
                imageData: nil,
                imageSize: imageSize,
                imagePath: imagePath,
                sourceTypes: [],
                capturedAt: createdAt,
                sourceAppName: sourceAppName,
                sourceAppBundleId: sourceAppBundleId
            )

            var metadata: [String: String] = [:]
            if let filePath { metadata["path"] = filePath }
            if let urlString { metadata["url"] = urlString }
            if width > 0 { metadata["width"] = String(width) }
            if height > 0 { metadata["height"] = String(height) }

            let item = ClipboardItem(
                id: id,
                createdAt: createdAt,
                type: type,
                previewTitle: previewTitle,
                metadata: metadata,
                contentHash: contentHash,
                sourceAppName: sourceAppName,
                sourceAppBundleId: sourceAppBundleId,
                pinned: pinned
            )
            results.append(ClipboardEntry(item: item, content: content))
        }

        return results
    }

    func save(entries: [ClipboardEntry]) -> [UUID: String] {
        let sql = """
        INSERT OR REPLACE INTO entries
        (id, created_at, type, preview_title, content_hash, text, url, file_path, image_path, image_width, image_height, source_app_name, source_app_bundle_id, pinned)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }

        var paths: [UUID: String] = [:]
        for entry in entries {
            let imagePath = saveImageIfNeeded(entry)
            if let imagePath {
                paths[entry.item.id] = imagePath
            }
            bindText(stmt, index: 1, value: entry.item.id.uuidString)
            sqlite3_bind_double(stmt, 2, entry.item.createdAt.timeIntervalSince1970)
            bindText(stmt, index: 3, value: entry.item.type.rawValue)
            bindText(stmt, index: 4, value: entry.item.previewTitle)
            bindText(stmt, index: 5, value: entry.item.contentHash)
            bindText(stmt, index: 6, value: entry.content.text)
            bindText(stmt, index: 7, value: entry.content.url?.absoluteString)
            bindText(stmt, index: 8, value: entry.content.fileURL?.path)
            bindText(stmt, index: 9, value: imagePath)
            if let size = entry.content.imageSize {
                sqlite3_bind_int(stmt, 10, Int32(size.width))
                sqlite3_bind_int(stmt, 11, Int32(size.height))
            } else {
                sqlite3_bind_null(stmt, 10)
                sqlite3_bind_null(stmt, 11)
            }
            bindText(stmt, index: 12, value: entry.item.sourceAppName)
            bindText(stmt, index: 13, value: entry.item.sourceAppBundleId)
            sqlite3_bind_int(stmt, 14, entry.item.pinned ? 1 : 0)

            _ = sqlite3_step(stmt)
            sqlite3_reset(stmt)
        }
        return paths
    }

    func delete(id: UUID) {
        let sql = "DELETE FROM entries WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, id.uuidString, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    func delete(ids: [UUID]) {
        guard !ids.isEmpty else { return }
        let placeholders = ids.map { _ in "?" }.joined(separator: ",")
        let sql = "DELETE FROM entries WHERE id IN (\(placeholders));"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        for (index, id) in ids.enumerated() {
            sqlite3_bind_text(stmt, Int32(index + 1), id.uuidString, -1, SQLITE_TRANSIENT)
        }
        _ = sqlite3_step(stmt)
    }

    func updatePinned(id: UUID, pinned: Bool) {
        let sql = "UPDATE entries SET pinned = ? WHERE id = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_int(stmt, 1, pinned ? 1 : 0)
        sqlite3_bind_text(stmt, 2, id.uuidString, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    private func openDatabase() {
        sqlite3_open(dbURL.path, &db)
        attemptEnableEncryption()
    }

    private func createTables() {
        let sql = """
        CREATE TABLE IF NOT EXISTS entries (
            id TEXT PRIMARY KEY,
            created_at REAL NOT NULL,
            type TEXT NOT NULL,
            preview_title TEXT NOT NULL,
            content_hash TEXT NOT NULL,
            text TEXT,
            url TEXT,
            file_path TEXT,
            image_path TEXT,
            image_width INTEGER,
            image_height INTEGER,
            source_app_name TEXT,
            source_app_bundle_id TEXT,
            pinned INTEGER DEFAULT 0
        );
        CREATE INDEX IF NOT EXISTS idx_entries_created_at ON entries(created_at DESC);
        CREATE INDEX IF NOT EXISTS idx_entries_hash ON entries(content_hash);
        """
        _ = sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func migrateIfNeeded() {
        if !columnExists("source_app_name") {
            _ = sqlite3_exec(db, "ALTER TABLE entries ADD COLUMN source_app_name TEXT;", nil, nil, nil)
        }
        if !columnExists("source_app_bundle_id") {
            _ = sqlite3_exec(db, "ALTER TABLE entries ADD COLUMN source_app_bundle_id TEXT;", nil, nil, nil)
        }
        if !columnExists("pinned") {
            _ = sqlite3_exec(db, "ALTER TABLE entries ADD COLUMN pinned INTEGER DEFAULT 0;", nil, nil, nil)
        }
    }

    private func attemptEnableEncryption() {
        guard !encryptionKey.isEmpty else { return }
        let escapedKey = encryptionKey.replacingOccurrences(of: "'", with: "''")
        _ = sqlite3_exec(db, "PRAGMA key = '\(escapedKey)';", nil, nil, nil)
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, "PRAGMA cipher_version;", -1, &stmt, nil) == SQLITE_OK {
            defer { sqlite3_finalize(stmt) }
            if sqlite3_step(stmt) == SQLITE_ROW {
                encryptionEnabled = true
            }
        }
        if !encryptionEnabled {
            print("Encryption not available; using plaintext SQLite.")
        }
    }

    private func saveImageIfNeeded(_ entry: ClipboardEntry) -> String? {
        guard let data = entry.content.imageData else { return nil }
        let path = imagesURL.appendingPathComponent("\(entry.item.id.uuidString).bin")
        do {
            try data.write(to: path, options: .atomic)
            return path.path
        } catch {
            return nil
        }
    }

    private func columnText(_ stmt: OpaquePointer?, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cString)
    }

    private func columnExists(_ name: String) -> Bool {
        let sql = "PRAGMA table_info(entries);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return false }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            if let columnName = columnText(stmt, index: 1), columnName == name {
                return true
            }
        }
        return false
    }

    private func bindText(_ stmt: OpaquePointer?, index: Int32, value: String?) {
        guard let value else {
            sqlite3_bind_null(stmt, index)
            return
        }
        sqlite3_bind_text(stmt, index, value, -1, SQLITE_TRANSIENT)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
