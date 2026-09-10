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
///   gancho save [--title <t>] [--language <id>] [--content-base64 <b64>]
///   gancho export [--csv] [--include-sensitive] [--out <path>]
///   gancho boards [--json]
///   gancho pin <clip-id> | unpin <clip-id>
///   gancho mcp --grant <grant-id>   # run one authorized stdio MCP session
///   gancho grant --client <name> --board <board-id> [policy options]
///   gancho status | enable | disable | revoke <grant-id>
///
/// `search`/`copy`/`save`/`export`/`boards`/`pin` are the user's own actions
/// and are not logged; the `mcp` server (which serves automated agents) logs
/// every access to the Privacy Center.
@main
struct GanchoCLI {
    // Keep the top-level command dispatch centralized; subcommands remain small
    // private helpers below.
    // swiftlint:disable:next cyclomatic_complexity
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
            case "save": try await runSave(args)
            case "export": try await runExport(args)
            case "boards": try await runBoards(args)
            case "pin": try await runSetPinned(args, pinned: true)
            case "unpin": try await runSetPinned(args, pinned: false)
            case "mcp": await runMCP(args)
            case "status": try await runStatus()
            case "enable": try runEnable(args)
            case "disable": try runDisable()
            case "grant": try await runGrant(args)
            case "revoke": try runRevoke(args)
            case "help", "--help", "-h": printUsage()
            default:
                printErr("Unknown command: \(command)")
                printUsage()
                exit(2)
            }
        } catch {
            printErr("gancho: \(error)")
            exit(1)
        }
    }

    // MARK: - Commands

    private static func runSearch(_ args: [String]) async throws {
        let options = Options(args)
        let query = options.positionals.joined(separator: " ")
        guard !query.isEmpty else {
            printErr(
                "usage: gancho search <query> [--limit N] [--mode exact|fuzzy|regex] [--json]")
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
            printRow("No clips matched “\(query)”.")
        } else {
            for item in hits {
                printRow(columns: [
                    item.id.uuidString, item.kind.rawValue, oneLine(item)
                ])
            }
        }
    }

    private static func runCopy(_ args: [String]) async throws {
        guard let raw = args.first, let id = UUID(uuidString: raw) else {
            printErr("usage: gancho copy <clip-id>")
            exit(2)
        }
        let store = try openStore()
        guard let content = try await store.content(for: id) else {
            printErr("No clip with id \(raw).")
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
            printRow("Copied clip \(raw) to the clipboard.")
        #else
            printErr("copy is only supported on macOS.")
            exit(1)
        #endif
    }

    /// Saves a selection straight into the Library as a code snippet — the
    /// editor/CLI funnel. Content arrives base64-encoded (so any bytes survive
    /// the argv round-trip) or piped on stdin. Writes directly to the local
    /// store: offline, no network, app need not be running.
    private static func runSave(_ args: [String]) async throws {
        let options = Options(args)
        let language = options.value("language")

        let text: String
        if let encoded = options.value("content-base64") {
            guard let data = Data(base64Encoded: encoded),
                let decoded = String(data: data, encoding: .utf8)
            else {
                printErr("gancho save: --content-base64 is not valid base64 UTF-8.")
                exit(2)
            }
            text = decoded
        } else {
            // No flag: take raw text from stdin (e.g. `pbpaste | gancho save`).
            text =
                String(data: FileHandle.standardInput.readDataToEndOfFile(), encoding: .utf8)
                ?? ""
        }
        guard !text.isEmpty else {
            printErr(
                "gancho save: empty content — pass --content-base64 <b64> or pipe text on stdin.")
            exit(2)
        }

        let title = options.value("title") ?? defaultTitle(from: text)
        let store = try openStore()
        let saved = try await store.saveSnippet(title: title, text: text, language: language)
        printRow("Saved snippet \(saved.id.uuidString)\(language.map { " [\($0)]" } ?? "").")
    }

    /// First non-empty line, trimmed and capped — a sensible snippet title
    /// when the caller doesn't pass `--title`.
    private static func defaultTitle(from text: String) -> String {
        let firstLine =
            text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        let base = firstLine.isEmpty ? "Snippet" : firstLine
        return base.count > 60 ? String(base.prefix(59)) + "…" : base
    }

    private static func runExport(_ args: [String]) async throws {
        let options = Options(args)
        let store = try openStore()
        // Sensitive clips are excluded unless explicitly opted in: an export
        // must not defeat the secret detector's short-expiry protection by
        // default. `--include-sensitive` restores the full dump.
        let excludeSensitive = !options.flag("include-sensitive")
        let data =
            options.flag("csv")
            ? try await store.exportCSV(excludeSensitive: excludeSensitive)
            : try await store.exportJSON(excludeSensitive: excludeSensitive)
        if let path = options.value("out") {
            try data.write(to: URL(fileURLWithPath: path))
            printRow("Exported \(ByteSize.formatted(data.count)) to \(path).")
        } else {
            printData(data)
        }
    }

    /// Lists the user's boards (id, symbol, name), tab-separated like
    /// `search`, or as JSON with `--json` — enough for shell scripts to pick
    /// a board id without opening the app.
    private static func runBoards(_ args: [String]) async throws {
        let options = Options(args)
        let store = try openStore()
        let boards = try await store.pinboards()
        if options.flag("json") {
            let payload = boards.map(CLIBoard.init)
            printData(try encodePretty(payload))
        } else if boards.isEmpty {
            printRow("No boards yet.")
        } else {
            for board in boards {
                printRow(columns: [
                    board.id.uuidString, board.sfSymbol, board.name
                ])
            }
        }
    }

    /// `gancho pin` / `gancho unpin`. Sensitive clips are refused outright —
    /// pinning would exempt a detector-flagged secret from the short-expiry
    /// retention that protects it, so the CLI mirrors the MCP veto.
    private static func runSetPinned(_ args: [String], pinned: Bool) async throws {
        let verb = pinned ? "pin" : "unpin"
        guard let raw = args.first, let id = UUID(uuidString: raw) else {
            printErr("usage: gancho \(verb) <clip-id>")
            exit(2)
        }
        let store = try openStore()
        guard let item = try await store.item(id: id) else {
            printErr("No clip with id \(raw).")
            exit(1)
        }
        if item.isSensitive {
            printErr("Clip \(raw) is sensitive; the CLI does not \(verb) sensitive clips.")
            exit(1)
        }
        try await store.setPinned(id: id, pinned)
        printRow("\(pinned ? "Pinned" : "Unpinned") clip \(raw).")
    }

    private static func runMCP(_ args: [String]) async {
        let directory = storeDirectory()
        let options = Options(args)
        let grantID = options.value("grant").flatMap(UUID.init(uuidString:))
        guard let store = try? GRDBClipboardStore.encrypted(directory: directory) else {
            printErr("gancho: could not open the store at \(directory.path).")
            exit(1)
        }
        let runner = MCPToolRunner(
            store: store,
            grantProvider: {
                MCPServerConfig.load(fromStoreDirectory: directory).resolveGrant(id: grantID)
            },
            log: { event in
                try? await store.recordMCPAccess(event)
            })
        // The runner owns the live enabled/grant checks. Keep the protocol edge
        // open so enabling or renewing can take effect without restarting stdio.
        let server = MCPServer(runner: runner, isEnabled: true)
        let resolution = MCPServerConfig.load(fromStoreDirectory: directory)
            .resolveGrant(id: grantID)
        switch resolution {
        case .active(let grant):
            printErr(
                "gancho mcp: ready for \(grant.safeClientName) "
                    + "(\(grant.scope.rawValue), \(grant.accessMode.rawValue)).")
            if grant.scope != .metadata {
                printErr(
                    "gancho mcp: content access is limited to the approved context pack.")
            }
        case .disabled:
            printErr("gancho mcp: ready, but MCP access is off in Gancho Settings.")
        case .missing:
            printErr(
                "gancho mcp: no valid --grant id; create a client grant in Gancho Settings.")
        case .invalidContext:
            printErr("gancho mcp: the selected grant has no explicit context pack.")
        case .expired:
            printErr("gancho mcp: the selected client grant expired.")
        case .revoked:
            printErr("gancho mcp: the selected client grant was revoked.")
        }
        await MCPStdioTransport(server: server).run()
    }

    private static func runStatus() async throws {
        let directory = storeDirectory()
        let config = MCPServerConfig.load(fromStoreDirectory: directory)
        let store = try openStore()
        let count = try await store.count()
        printRow("store:   \(directory.path)")
        printRow("clips:   \(count)")
        printRow(
            "mcp:     \(config.isEnabled ? "enabled" : "disabled") "
                + "(\(config.activeGrants.count) active client grants)"
        )
        for grant in config.grants {
            printRow(columns: [
                "grant:   \(grant.id.uuidString)", grant.state().rawValue,
                grant.accessMode.rawValue, grant.scope.rawValue, grant.safeClientName
            ])
        }
    }

    private static func runEnable(_: [String]) throws {
        let directory = storeDirectory()
        var config = MCPServerConfig.load(fromStoreDirectory: directory)
        config.isEnabled = true
        try config.save(toStoreDirectory: directory)
        printRow("MCP access enabled. Each client still needs an active grant.")
    }

    private static func runDisable() throws {
        let current = MCPServerConfig.load(fromStoreDirectory: storeDirectory())
        var updated = current
        updated.isEnabled = false
        try updated.save(toStoreDirectory: storeDirectory())
        printRow("MCP access disabled.")
    }

    private static func runGrant(_ args: [String]) async throws {
        let options = Options(args)
        guard
            let rawClient = options.value("client")?.trimmingCharacters(
                in: .whitespacesAndNewlines),
            !rawClient.isEmpty,
            let rawBoard = options.value("board"),
            let boardID = UUID(uuidString: rawBoard)
        else {
            printErr(
                "usage: gancho grant --client <name> --board <board-id> "
                    + "[--scope metadata|boards|all] [--write] "
                    + "[--time last-hour|last-day|last-week|last-month|all-time] "
                    + "[--expires-hours N]")
            exit(2)
        }

        let store = try openStore()
        guard let board = try await store.pinboards().first(where: { $0.id == boardID }) else {
            printErr("No board with id \(rawBoard). Run `gancho boards --json` first.")
            exit(2)
        }
        let rawScope = options.value("scope") ?? MCPAccessScope.metadata.rawValue
        guard let scope = MCPAccessScope(rawValue: rawScope) else {
            printErr("Invalid --scope value: \(rawScope). Use metadata, boards, or all.")
            exit(2)
        }
        let rawTimeScope = options.value("time") ?? MCPTimeScope.lastWeek.rawValue
        guard let timeScope = MCPTimeScope(rawValue: rawTimeScope) else {
            printErr(
                "Invalid --time value: \(rawTimeScope). Use last-hour, last-day, "
                    + "last-week, last-month, or all-time.")
            exit(2)
        }
        let requestedExpiryHours: Int
        if let rawExpiry = options.value("expires-hours") {
            guard let parsed = Int(rawExpiry), parsed > 0 else {
                printErr("Invalid --expires-hours value: \(rawExpiry). Use a positive integer.")
                exit(2)
            }
            requestedExpiryHours = parsed
        } else {
            requestedExpiryHours = 168
        }
        let expiryHours = min(requestedExpiryHours, 24 * 365)
        let grant = MCPClientGrant(
            clientName: String(rawClient.prefix(MCPClientGrant.maximumClientNameLength)),
            scope: scope,
            accessMode: options.flag("write") ? .readWrite : .readOnly,
            contextPack: MCPContextPack(
                name: board.name,
                boardID: board.id,
                boardName: board.name,
                timeScope: timeScope),
            expiresAt: Date().addingTimeInterval(Double(expiryHours) * 60 * 60))

        let directory = storeDirectory()
        var config = MCPServerConfig.load(fromStoreDirectory: directory)
        config.isEnabled = true
        config.grants.append(grant)
        try config.save(toStoreDirectory: directory)
        printRow("Created grant \(grant.id.uuidString) for \(grant.safeClientName).")
        printRow("Connect with: gancho mcp --grant \(grant.id.uuidString)")
    }

    private static func runRevoke(_ args: [String]) throws {
        guard let rawID = args.first, let id = UUID(uuidString: rawID) else {
            printErr("usage: gancho revoke <grant-id>")
            exit(2)
        }
        let directory = storeDirectory()
        var config = MCPServerConfig.load(fromStoreDirectory: directory)
        guard let index = config.grants.firstIndex(where: { $0.id == id }) else {
            printErr("No client grant with id \(rawID).")
            exit(2)
        }
        config.grants[index].revokedAt = .now
        try config.save(toStoreDirectory: directory)
        printRow("Revoked client grant \(rawID). New calls now fail closed.")
    }

    // MARK: - Helpers

    /// The store directory: the app's by default, overridable with
    /// `GANCHO_STORE_DIR` (handy for tests and alternate profiles).
    private static func storeDirectory() -> URL {
        CLIFormatting.storeDirectory()
    }

    private static func openStore() throws -> GRDBClipboardStore {
        try GRDBClipboardStore.encrypted(directory: storeDirectory())
    }

    private static func mode(_ raw: String?) -> ClipSearchQuery.Mode {
        CLIFormatting.mode(raw)
    }

    private static func oneLine(_ item: ClipItem) -> String {
        CLIFormatting.oneLine(item)
    }

    /// One row on stdout, flattened.
    ///
    /// The CLI's only `print` path, so the guarantee is structural rather than
    /// remembered per call site: rows are tab-separated or label-aligned, and
    /// almost every one interpolates something the CLI did not choose — a
    /// board name, a store path, an argument echoed back. A bare CR in any of
    /// them returns the cursor to column 0 and overwrites the columns already
    /// written; a TAB opens a phantom one.
    ///
    /// `--json` output does not come through here and does not need to: it
    /// goes out via ``printData(_:)`` and JSON escapes control characters by
    /// construction, so the machine-readable format stays byte-exact.
    private static func printRow(_ line: String) {
        emit(CLIFormatting.flattened(line))
    }

    /// One tab-separated row. Columns are sanitized individually and joined
    /// with delimiters this file owns, so a clip preview or a board name can
    /// never forge a column boundary — and, just as importantly, flattening
    /// can never eat one. `search`, `boards` and the `status` grant list are
    /// documented as tab-separated and stay machine-parseable.
    private static func printRow(columns: [String]) {
        emit(CLIFormatting.row(columns))
    }

    /// The single `print` in this file: everything reaches it already
    /// sanitized, so the guard test only has to police one call.
    private static func emit(_ line: String) {
        print(line)
    }

    private static func encodePretty(_ value: some Encodable) throws -> Data {
        try CLIFormatting.encodePretty(value)
    }

    private static func printData(_ data: Data) {
        FileHandle.standardOutput.write(data)
        if data.last != 0x0A { FileHandle.standardOutput.write(Data([0x0A])) }
    }

    /// One diagnostic row on stderr.
    ///
    /// Flattens for the same reason ``printRow(_:)`` does — a diagnostic
    /// echoes back the argument or path the user passed, and stderr is the
    /// same terminal — and owns the trailing newline so the flattening cannot
    /// eat a caller's.
    private static func printErr(_ message: String) {
        FileHandle.standardError.write(Data(CLIFormatting.diagnostic(message).utf8))
    }

    /// The only multi-line output the CLI produces on purpose, so it goes out
    /// as bytes rather than through ``printRow(_:)`` — flattening it would
    /// collapse the whole help screen onto one line. It is a fixed literal
    /// with nothing interpolated, so there is nothing here to sanitize.
    private static func printUsage() {
        printData(
            Data(
                """
                gancho — the Gancho clipboard CLI

                USAGE:
                  gancho search <query> [--limit N] [--mode exact|fuzzy|regex] [--json]
                  gancho copy <clip-id>
                  gancho save [--title <t>] [--language <id>] [--content-base64 <b64>]
                  gancho export [--csv] [--include-sensitive] [--out <path>]
                  gancho boards [--json]
                  gancho pin <clip-id>
                  gancho unpin <clip-id>
                  gancho mcp --grant <grant-id>
                  gancho status
                  gancho enable
                  gancho disable
                  gancho grant --client <name> --board <board-id> [--scope metadata|boards|all]
                               [--write] [--time last-hour|last-day|last-week|last-month|all-time]
                               [--expires-hours N]
                  gancho revoke <grant-id>

                Exports skip detector-flagged sensitive clips unless you pass
                --include-sensitive. The MCP server (gancho mcp) is opt-in and OFF
                by default. Each MCP process needs a client grant created in Gancho
                Settings or with `gancho grant`; revoke applies to its next call.
                """.utf8))
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

/// Wire shape for `gancho boards --json` (the human format is tab-separated).
private struct CLIBoard: Encodable {
    let id: String
    let name: String
    let sfSymbol: String

    init(board: Pinboard) {
        id = board.id.uuidString
        name = board.name
        sfSymbol = board.sfSymbol
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
