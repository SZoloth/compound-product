import XCTest
@testable import PasteyCLI

final class PasteyCLIE2ETests: XCTestCase {
    private func requireE2EEnabled() throws -> Int {
        let env = ProcessInfo.processInfo.environment
        guard env["PASTEY_E2E"] == "1" else {
            throw XCTSkip("Set PASTEY_E2E=1 to enable end-to-end tests.")
        }
        let portString = env["PASTEY_PORT"] ?? "8899"
        return Int(portString) ?? 8899
    }

    func testHealthEndpointAgainstRunningServer() throws {
        let port = try requireE2EEnabled()
        let options = CLIOptions(command: "health", query: nil, limit: 1, type: nil, pinnedOnly: false, port: port, jsonOutput: true)
        guard let url = buildURL(options: options) else {
            XCTFail("Expected URL")
            return
        }

        guard let data = fetch(url) else {
            XCTFail("Pastey Local API not reachable. Ensure the app is running and Local API is enabled.")
            return
        }
        let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["status"] as? String, "ok")
    }

    func testRecentEndpointAgainstRunningServer() throws {
        let port = try requireE2EEnabled()
        let options = CLIOptions(command: "recent", query: nil, limit: 5, type: nil, pinnedOnly: false, port: port, jsonOutput: true)
        guard let url = buildURL(options: options) else {
            XCTFail("Expected URL")
            return
        }

        guard let data = fetch(url) else {
            XCTFail("Pastey Local API not reachable. Ensure the app is running and Local API is enabled.")
            return
        }
        let json = try? JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(json as? [[String: Any]])
    }

    func testSearchEndpointAgainstRunningServer() throws {
        let port = try requireE2EEnabled()
        let options = CLIOptions(command: "search", query: "test", limit: 5, type: nil, pinnedOnly: false, port: port, jsonOutput: true)
        guard let url = buildURL(options: options) else {
            XCTFail("Expected URL")
            return
        }

        guard let data = fetch(url) else {
            XCTFail("Pastey Local API not reachable. Ensure the app is running and Local API is enabled.")
            return
        }
        let json = try? JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(json as? [[String: Any]])
    }
}
