import Foundation

struct CLIOptions {
    var command: String
    var query: String?
    var limit: Int = 50
    var type: String?
    var pinnedOnly: Bool = false
    var port: Int = 8899
    var jsonOutput: Bool = false
}

final class FetchResult: @unchecked Sendable {
    var data: Data?
    var error: Error?
}

func printUsage() {
    let usage = """
PasteyCLI

Usage:
  PasteyCLI search <query> [--limit N] [--type text|image|file|url|unknown] [--pinned] [--port N] [--json]
  PasteyCLI recent [--limit N] [--port N] [--json]
  PasteyCLI health [--port N]

Examples:
  PasteyCLI search "raycast" --limit 20
  PasteyCLI search "invoice" --type file
  PasteyCLI recent --limit 10
"""
    print(usage)
}

func parseArgs(_ args: [String]) -> CLIOptions? {
    guard args.count >= 2 else { return nil }

    var options = CLIOptions(command: args[1])
    var index = 2
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--limit":
            if index + 1 < args.count, let value = Int(args[index + 1]) {
                options.limit = value
                index += 2
                continue
            }
            return nil
        case "--type":
            if index + 1 < args.count {
                options.type = args[index + 1]
                index += 2
                continue
            }
            return nil
        case "--pinned":
            options.pinnedOnly = true
            index += 1
            continue
        case "--port":
            if index + 1 < args.count, let value = Int(args[index + 1]) {
                options.port = value
                index += 2
                continue
            }
            return nil
        case "--json":
            options.jsonOutput = true
            index += 1
            continue
        case "-h", "--help":
            return nil
        default:
            if options.command == "search" && options.query == nil {
                options.query = arg
                index += 1
                continue
            }
            return nil
        }
    }

    return options
}

func parseArgs() -> CLIOptions? {
    parseArgs(CommandLine.arguments)
}

func buildURL(options: CLIOptions) -> URL? {
    var components = URLComponents()
    components.scheme = "http"
    components.host = "127.0.0.1"
    components.port = options.port

    switch options.command {
    case "health":
        components.path = "/health"
    case "recent":
        components.path = "/recent"
        components.queryItems = [URLQueryItem(name: "limit", value: String(options.limit))]
    case "search":
        components.path = "/search"
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: String(options.limit))
        ]
        if let query = options.query {
            items.append(URLQueryItem(name: "q", value: query))
        }
        if let type = options.type {
            items.append(URLQueryItem(name: "type", value: type))
        }
        if options.pinnedOnly {
            items.append(URLQueryItem(name: "pinned", value: "1"))
        }
        components.queryItems = items
    default:
        return nil
    }

    return components.url
}

func fetch(_ url: URL) -> Data? {
    let semaphore = DispatchSemaphore(value: 0)
    let result = FetchResult()
    var request = URLRequest(url: url)
    request.timeoutInterval = 5
    let task = URLSession.shared.dataTask(with: request) { data, _, error in
        result.data = data
        result.error = error
        semaphore.signal()
    }
    task.resume()
    _ = semaphore.wait(timeout: .now() + 5)
    if let error = result.error {
        fputs("Error: \(error)\n", stderr)
    }
    return result.data
}

func printItems(from data: Data) {
    guard let json = try? JSONSerialization.jsonObject(with: data) else {
        print(String(decoding: data, as: UTF8.self))
        return
    }

    if let dict = json as? [String: Any] {
        if let pretty = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]) {
            print(String(decoding: pretty, as: UTF8.self))
        } else {
            print(dict)
        }
        return
    }

    guard let items = json as? [[String: Any]] else {
        print(String(decoding: data, as: UTF8.self))
        return
    }

    for item in items {
        let type = item["type"] as? String ?? "unknown"
        let preview = item["preview"] as? String ?? ""
        let source = item["source_app_name"] as? String ?? "Unknown"
        let pinned = (item["pinned"] as? Bool) == true ? "★ " : ""
        let trimmedPreview = preview.count > 120 ? String(preview.prefix(120)) + "…" : preview
        print("\(pinned)[\(type)] \(trimmedPreview) — \(source)")
    }
}

guard let options = parseArgs() else {
    printUsage()
    exit(1)
}

if options.command == "search" && (options.query == nil || options.query?.isEmpty == true) {
    print("Missing search query.\n")
    printUsage()
    exit(1)
}

guard let url = buildURL(options: options) else {
    printUsage()
    exit(1)
}

guard let data = fetch(url) else {
    print("Pastey Local API not reachable. Enable it in Preferences and verify the port.")
    exit(1)
}

if options.jsonOutput {
    print(String(decoding: data, as: UTF8.self))
} else {
    printItems(from: data)
}
