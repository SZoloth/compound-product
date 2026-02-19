import Foundation
import Network
import XCTest
@testable import PasteyCLI

final class PasteyCLIIntegrationTests: XCTestCase {
    private final class MockLocalAPIServer: @unchecked Sendable {
        private let listener: NWListener
        private let queue = DispatchQueue(label: "PasteyCLIIntegrationTests.server")
        private let readySemaphore = DispatchSemaphore(value: 0)

        init() throws {
            listener = try NWListener(using: .tcp, on: 0)
            listener.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready, .failed:
                    self?.readySemaphore.signal()
                default:
                    break
                }
            }
        }

        var port: UInt16 {
            listener.port?.rawValue ?? 0
        }

        func start() throws {
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.start(queue: queue)
            if readySemaphore.wait(timeout: .now() + 1) == .timedOut {
                throw NSError(domain: "PasteyCLIIntegrationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server did not start"])
            }
        }

        func stop() {
            listener.cancel()
        }

        private func handle(_ connection: NWConnection) {
            connection.start(queue: queue)
            receiveRequest(on: connection, buffer: Data())
        }

        private func receiveRequest(on connection: NWConnection, buffer: Data) {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, isComplete, _ in
                guard let self else { return }
                var updated = buffer
                if let data {
                    updated.append(data)
                }
                if updated.range(of: Data("\r\n\r\n".utf8)) != nil || isComplete {
                    self.respond(to: updated, connection: connection)
                } else {
                    self.receiveRequest(on: connection, buffer: updated)
                }
            }
        }

        private func respond(to requestData: Data, connection: NWConnection) {
            let request = String(decoding: requestData, as: UTF8.self)
            let firstLine = request.split(separator: "\r\n").first ?? ""
            let parts = firstLine.split(separator: " ")
            let rawPath = parts.count > 1 ? String(parts[1]) : "/"

            let components = URLComponents(string: "http://127.0.0.1\(rawPath)")
            let path = components?.path ?? "/"
            let queryItems = components?.queryItems ?? []

            let body: String
            switch path {
            case "/health":
                body = #"{"status":"ok"}"#
            case "/recent":
                body = #"[{"id":"1","type":"text","preview":"Recent item","source_app_name":"Notes","pinned":false}]"#
            case "/search":
                let query = queryItems.first(where: { $0.name == "q" })?.value ?? ""
                body = #"[{"id":"2","type":"text","preview":"Search: \#(query)","source_app_name":"Mail","pinned":true}]"#
            default:
                body = #"{"error":"not_found"}"#
            }

            let response = """
HTTP/1.1 200 OK\r
Content-Type: application/json\r
Content-Length: \(body.utf8.count)\r
Connection: close\r
\r
\(body)
"""
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }

    func testHealthEndpointFetch() throws {
        let server = try MockLocalAPIServer()
        try server.start()
        defer { server.stop() }

        let options = CLIOptions(command: "health", query: nil, limit: 1, type: nil, pinnedOnly: false, port: Int(server.port), jsonOutput: true)
        guard let url = buildURL(options: options) else {
            XCTFail("Expected URL")
            return
        }

        let data = fetch(url)
        XCTAssertNotNil(data)
        let json = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any]
        XCTAssertEqual(json?["status"] as? String, "ok")
    }

    func testSearchEndpointFetch() throws {
        let server = try MockLocalAPIServer()
        try server.start()
        defer { server.stop() }

        let options = CLIOptions(command: "search", query: "alpha", limit: 5, type: nil, pinnedOnly: true, port: Int(server.port), jsonOutput: false)
        guard let url = buildURL(options: options) else {
            XCTFail("Expected URL")
            return
        }

        let data = fetch(url)
        XCTAssertNotNil(data)
        let items = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [[String: Any]]
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?["preview"] as? String, "Search: alpha")
        XCTAssertEqual(items?.first?["pinned"] as? Bool, true)
    }

    func testRecentEndpointFetch() throws {
        let server = try MockLocalAPIServer()
        try server.start()
        defer { server.stop() }

        let options = CLIOptions(command: "recent", query: nil, limit: 3, type: nil, pinnedOnly: false, port: Int(server.port), jsonOutput: false)
        guard let url = buildURL(options: options) else {
            XCTFail("Expected URL")
            return
        }

        let data = fetch(url)
        XCTAssertNotNil(data)
        let items = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [[String: Any]]
        XCTAssertEqual(items?.count, 1)
        XCTAssertEqual(items?.first?["preview"] as? String, "Recent item")
    }
}
