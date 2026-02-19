import XCTest
@testable import PasteyCLI

final class PasteyCLITests: XCTestCase {
    func testParseArgsRequiresCommand() {
        XCTAssertNil(parseArgs(["PasteyCLI"]))
    }

    func testParseArgsSearch() {
        let options = parseArgs(["PasteyCLI", "search", "raycast", "--limit", "25", "--type", "text", "--pinned", "--port", "9001", "--json"])
        XCTAssertEqual(options?.command, "search")
        XCTAssertEqual(options?.query, "raycast")
        XCTAssertEqual(options?.limit, 25)
        XCTAssertEqual(options?.type, "text")
        XCTAssertEqual(options?.pinnedOnly, true)
        XCTAssertEqual(options?.port, 9001)
        XCTAssertEqual(options?.jsonOutput, true)
    }

    func testBuildURLForSearch() {
        let options = CLIOptions(
            command: "search",
            query: "invoice",
            limit: 10,
            type: "file",
            pinnedOnly: true,
            port: 8899,
            jsonOutput: false
        )
        let url = buildURL(options: options)
        XCTAssertEqual(url?.scheme, "http")
        XCTAssertEqual(url?.host, "127.0.0.1")
        XCTAssertEqual(url?.port, 8899)
        XCTAssertEqual(url?.path, "/search")
        XCTAssertEqual(url?.query?.contains("q=invoice"), true)
        XCTAssertEqual(url?.query?.contains("limit=10"), true)
        XCTAssertEqual(url?.query?.contains("type=file"), true)
        XCTAssertEqual(url?.query?.contains("pinned=1"), true)
    }

    func testBuildURLForRecent() {
        let options = CLIOptions(
            command: "recent",
            query: nil,
            limit: 7,
            type: nil,
            pinnedOnly: false,
            port: 8899,
            jsonOutput: false
        )
        let url = buildURL(options: options)
        XCTAssertEqual(url?.path, "/recent")
        XCTAssertEqual(url?.query, "limit=7")
    }
}
