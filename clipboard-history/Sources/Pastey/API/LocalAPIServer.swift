import Foundation
import Network

final class LocalAPIServer: @unchecked Sendable {
    private let store: ClipboardHistoryStore
    private var listener: NWListener?
    private let queue = DispatchQueue(label: "pastey.local.api")
    private let dateFormatter = ISO8601DateFormatter()

    init(store: ClipboardHistoryStore) {
        self.store = store
    }

    func start(port: Int) {
        stop()
        guard let port = NWEndpoint.Port(rawValue: UInt16(port)) else { return }
        do {
            listener = try NWListener(using: .tcp, on: port)
        } catch {
            print("Local API failed to start: \(error)")
            return
        }

        listener?.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }
        listener?.start(queue: queue)
        print("Local API listening on http://127.0.0.1:\(port)")
    }

    func stop() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self, let data else {
                connection.cancel()
                return
            }
            let request = String(decoding: data, as: UTF8.self)
            guard let line = request.split(separator: "\r\n").first else {
                self.respond(connection, status: 400, body: self.json(["error": "bad_request"]))
                return
            }
            let parts = line.split(separator: " ")
            guard parts.count >= 2 else {
                self.respond(connection, status: 400, body: self.json(["error": "bad_request"]))
                return
            }
            let method = parts[0]
            let path = parts[1]
            guard method == "GET" else {
                self.respond(connection, status: 405, body: self.json(["error": "method_not_allowed"]))
                return
            }

            let urlString = "http://127.0.0.1\(path)"
            guard let components = URLComponents(string: urlString) else {
                self.respond(connection, status: 400, body: self.json(["error": "bad_request"]))
                return
            }

            switch components.path {
            case "/health":
                self.respond(connection, status: 200, body: self.json(["ok": true, "app": "Pastey"]))
            case "/recent":
                let limit = self.intQuery(components, name: "limit", fallback: 50)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let items = self.store.entries.prefix(max(1, min(limit, 200))).map { self.apiItem(from: $0) }
                    self.respond(connection, status: 200, body: self.json(items))
                }
            case "/search":
                let query = self.stringQuery(components, name: "q")?.lowercased()
                let limit = self.intQuery(components, name: "limit", fallback: 50)
                let type = self.stringQuery(components, name: "type").flatMap(ClipboardItemType.init(rawValue:))
                let pinnedOnly = self.boolQuery(components, name: "pinned")
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    let results = self.store.search(query: query, type: type, pinnedOnly: pinnedOnly, limit: limit)
                    let items = results.map { self.apiItem(from: $0) }
                    self.respond(connection, status: 200, body: self.json(items))
                }
            case "/item":
                guard let idString = self.stringQuery(components, name: "id"), let id = UUID(uuidString: idString) else {
                    self.respond(connection, status: 400, body: self.json(["error": "missing_id"]))
                    return
                }
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    if let entry = self.store.entry(id: id) {
                        self.respond(connection, status: 200, body: self.json(self.apiItem(from: entry)))
                    } else {
                        self.respond(connection, status: 404, body: self.json(["error": "not_found"]))
                    }
                }
            default:
                self.respond(connection, status: 404, body: self.json(["error": "not_found"]))
            }
        }
    }

    private func apiItem(from entry: ClipboardEntry) -> [String: Any] {
        var payload: [String: Any] = [
            "id": entry.item.id.uuidString,
            "created_at": dateFormatter.string(from: entry.item.createdAt),
            "type": entry.item.type.rawValue,
            "preview": entry.item.previewTitle,
            "pinned": entry.item.pinned
        ]
        if let text = entry.content.text { payload["text"] = text }
        if let url = entry.content.url?.absoluteString { payload["url"] = url }
        if let file = entry.content.fileURL?.path { payload["file_path"] = file }
        if let imagePath = entry.content.imagePath { payload["image_path"] = imagePath }
        if let size = entry.content.imageSize {
            payload["image_width"] = Int(size.width)
            payload["image_height"] = Int(size.height)
        }
        if let source = entry.item.sourceAppName { payload["source_app_name"] = source }
        if let bundle = entry.item.sourceAppBundleId { payload["source_app_bundle_id"] = bundle }
        return payload
    }

    private func json(_ object: Any) -> Data {
        if let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]) {
            return data
        }
        return Data("{}".utf8)
    }

    private func respond(_ connection: NWConnection, status: Int, body: Data) {
        let statusLine = "HTTP/1.1 \(status) \(statusText(status))\r\n"
        let headers = "Content-Type: application/json\r\nContent-Length: \(body.count)\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        let response = Data((statusLine + headers).utf8) + body
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func statusText(_ code: Int) -> String {
        switch code {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        default: return "Error"
        }
    }

    private func stringQuery(_ components: URLComponents, name: String) -> String? {
        components.queryItems?.first(where: { $0.name == name })?.value
    }

    private func intQuery(_ components: URLComponents, name: String, fallback: Int) -> Int {
        if let value = stringQuery(components, name: name), let int = Int(value) {
            return int
        }
        return fallback
    }

    private func boolQuery(_ components: URLComponents, name: String) -> Bool {
        guard let value = stringQuery(components, name: name) else { return false }
        return value == "1" || value.lowercased() == "true"
    }
}
