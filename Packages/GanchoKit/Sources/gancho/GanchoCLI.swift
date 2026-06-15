import Foundation
import GanchoKit
import GanchoMCP

#if canImport(AppKit)
    import AppKit
#endif

/// The `gancho` command-line tool, distributed via Homebrew. It opens the
/// SAME local database as the macOS app (the app is unsandboxed, so the path
/// resolves identically) and offers the DevEx Maccy/Raycast users expect:
///
///   gancho search <query> [--limit N] [--mode exact|fuzzy|regex] [--json]
///   gancho copy <clip-id>
///   gancho export [--csv] [--out <path>]
///   gancho mcp                      # run the stdio MCP server
///   gancho status | enable [--scope metadata|boards|all] | disable
///
/// `search`/`copy`/`export` are the user's own actions and are not logged;
/// the `mcp` server (which serves automated agents) logs every access to the
/// Privacy Center.
@main
struct GanchoCLI {
    static func main() async {
        var args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            printUsage()
            return
        }
        args.removeFirst()

        do {
            switch command {
            case "search": try await runSearch(args)
            case "copy": try await runCopy(args)
            case "export": try await runExport(args)
            case "mcp": await runMCP()
            case "status": try await runStatus()
            case "enable": try runEnable(args)
            case "disable": try runDisable()
            case "help", "--help", "-h": printUsage()
            default:
                printErr("Unknown command: \(command)\n")
                printUsage()
                exit(2)
            }
        } catch {
            printErr("gancho: \(error)\n")
            exit(1)
        }
    }

    // MARK: - Commands

    private static func runSearch(_ args: [String]) async throws {
        let options = Options(args)
        let query = options.positionals.joined(separator: " ")
        guard !query.isEmpty else {
            printErr(
                "usage: gancho search <query> [--limit N] [--mode exact|fuzzy|regex] [--json]\n")
            exit(2)
        }
        let store = try openStore()
        let limit = options.int("limit") ?? 25
        let q = ClipSearchQuery(text: query, mode: mode(options.value("mode")))
        let hits = try await store.search(q, limit: min(max(limit, 1), 200))

        if options.flag("json") {
            let payload = hits.map(CLIClip.init)
            printData(try encodePretty(payload))
        } else if hits.isEmpty {
            print("No clips matched “\(query)”.")
        } else {
            for item in hits {
                let line = "\(item.id.uuidString)\t\(item.kind.rawValue)\t\(oneLine(item))"
                print(line)
            }
        }
    }

    private static func runCopy(_ args: [String]) async throws {
        guard let raw = args.first, let id = UUID(uuidString: raw) else {
            printErr("usage: gancho copy <clip-id>\n")
            exit(2)
        }
        let store = try openStore()
        guard let content = try await store.content(for: id) else {
            printErr("No clip with id \(raw).\n")
            exit(1)
        }
        #if canImport(AppKit)
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            switch content {
            case .text(let text):
                pasteboard.setString(text, forType: .string)
            case .fileReferences(let paths):
                pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
            case .binary(let data, let type):
                pasteboard.setData(data, forType: NSPasteboard.PasteboardType(type))
            }
            print("Copied clip \(raw) to the clipboard.")
        #else
            printErr("copy is only supported on macOS.\n")
            exit(1)
        #endif
    }

    private static func runExport(_ args: [String]) async throws {
        let options = Options(args)
        let store = try openStore()
        let data = options.flag("csv") ? try await store.exportCSV() : try await store.exportJSON()
        if let path = options.value("out") {
            try data.write(to: URL(fileURLWithPath: path))
            print("Exported \(data.count) bytes to \(path).")
        } else {
            printData(data)
        }
    }

    private static func runMCP() async {
        let directory = storeDirectory()
        let config = MCPServerConfig.load(fromStoreDirectory: directory)
        guard let store = try? GRDBClipboardStore(directory: directory) else {
            printErr("gancho: could not open the store at \(directory.path).\n")
            exit(1)
        }
        let runner = MCPToolRunner(store: store, scope: config.scope) { event in
            try? await store.recordMCPAccess(event)
        }
        let server = MCPServer(runner: runner, isEnabled: config.isEnabled)
        printErr(
            "gancho mcp: ready (access \(config.isEnabled ? "ON, scope \(config.scope.rawValue)" : "OFF")).\n"
        )
        await MCPStdioTransport(server: server).run()
    }

    private static func runStatus() async throws {
        let directory = storeDirectory()
        let config = MCPServerConfig.load(fromStoreDirectory: directory)
        let store = try openStore()
        let count = try await store.count()
        print("store:   \(directory.path)")
        print("clips:   \(count)")
        print(
            "mcp:     \(config.isEnabled ? "enabled" : "disabled") (scope: \(config.scope.rawValue))"
        )
    }

    private static func runEnable(_ args: [String]) throws {
        let options = Options(args)
        let scope = MCPAccessScope(rawValue: options.value("scope") ?? "metadata") ?? .metadata
        try MCPServerConfig(isEnabled: true, scope: scope).save(toStoreDirectory: storeDirectory())
        print("MCP access enabled (scope: \(scope.rawValue)).")
    }

    private static func runDisable() throws {
        let current = MCPServerConfig.load(fromStoreDirectory: storeDirectory())
        try MCPServerConfig(isEnabled: false, scope: current.scope)
            .save(toStoreDirectory: storeDirectory())
        print("MCP access disabled.")
    }

    // MARK: - Helpers

    /// The store directory: the app's by default, overridable with
    /// `GANCHO_STORE_DIR` (handy for tests and alternate profiles).
    private static func storeDirectory() -> URL {
        if let override = ProcessInfo.processInfo.environment["GANCHO_STORE_DIR"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return SharedStorageLocation.macAppStoreDirectory
    }

    private static func openStore() throws -> GRDBClipboardStore {
        try GRDBClipboardStore(directory: storeDirectory())
    }

    private static func mode(_ raw: String?) -> ClipSearchQuery.Mode {
        switch raw?.lowercased() {
        case "exact": return .exact
        case "regex": return .regex
        default: return .fuzzy
        }
    }

    private static func oneLine(_ item: ClipItem) -> String {
        let text = item.title.isEmpty ? item.preview : item.title
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
        return collapsed.count > 80 ? String(collapsed.prefix(79)) + "…" : collapsed
    }

    private static func encodePretty(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    private static func printData(_ data: Data) {
        FileHandle.standardOutput.write(data)
        if data.last != 0x0A { FileHandle.standardOutput.write(Data([0x0A])) }
    }

    private static func printErr(_ message: String) {
        FileHandle.standardError.write(Data(message.utf8))
    }

    private static func printUsage() {
        print(
            """
            gancho — the Gancho clipboard CLI

            USAGE:
              gancho search <query> [--limit N] [--mode exact|fuzzy|regex] [--json]
              gancho copy <clip-id>
              gancho export [--csv] [--out <path>]
              gancho mcp
              gancho status
              gancho enable [--scope metadata|boards|all]
              gancho disable

            The MCP server (gancho mcp) is opt-in and OFF by default; enable it
            from Gancho → Settings or with `gancho enable`.
            """)
    }
}

/// Wire shape for `gancho search --json` (the human format is tab-separated).
private struct CLIClip: Encodable {
    let id: String
    let kind: String
    let title: String
    let preview: String
    let isPinned: Bool
    let createdAt: Date

    init(item: ClipItem) {
        id = item.id.uuidString
        kind = item.kind.rawValue
        title = item.title
        preview = item.preview
        isPinned = item.isPinned
        createdAt = item.createdAt
    }
}

/// Dead-simple flag parser: `--key value`, `--flag`, and positionals. No
/// dependency on swift-argument-parser — the surface is four verbs.
private struct Options {
    private(set) var positionals: [String] = []
    private var values: [String: String] = [:]
    private var flags: Set<String> = []

    init(_ args: [String]) {
        var index = 0
        while index < args.count {
            let token = args[index]
            if token.hasPrefix("--") {
                let key = String(token.dropFirst(2))
                if index + 1 < args.count, !args[index + 1].hasPrefix("--") {
                    values[key] = args[index + 1]
                    index += 2
                } else {
                    flags.insert(key)
                    index += 1
                }
            } else {
                positionals.append(token)
                index += 1
            }
        }
    }

    func value(_ key: String) -> String? { values[key] }
    func int(_ key: String) -> Int? { values[key].flatMap(Int.init) }
    func flag(_ key: String) -> Bool { flags.contains(key) }
}
