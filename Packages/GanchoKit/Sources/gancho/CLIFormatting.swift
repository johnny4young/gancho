import Foundation
import GanchoKit

/// The `gancho` CLI's pure decisions, lifted out of the executable so they can
/// be tested at all.
///
/// The executable is `@main` with everything `private static`, which is fine
/// for wiring but meant that none of this had a single test — in a binary
/// distributed through Homebrew. What lives here is exactly the part with no
/// I/O: how an option string becomes a mode, how a row is summarized for a
/// terminal, what shape the JSON takes, and where the store is read from.
enum CLIFormatting {
    /// Longest single-line summary the list output will print, ellipsis
    /// included. Terminal-friendly rather than a hard requirement.
    static let summaryWidth = 80

    /// Search mode from `--mode`. Unrecognized input falls back to fuzzy
    /// rather than failing: a typo should still search, not abort.
    static func mode(_ raw: String?) -> ClipSearchQuery.Mode {
        switch raw?.lowercased() {
        case "exact": return .exact
        case "regex": return .regex
        default: return .fuzzy
        }
    }

    /// One terminal line for a clip: its title when it has one, else the
    /// preview, newlines flattened so a multi-line clip cannot break the
    /// column layout, and truncated with an ellipsis.
    ///
    /// The result never exceeds ``summaryWidth`` INCLUDING the ellipsis — the
    /// ellipsis replaces a character rather than being appended past the limit.
    static func oneLine(_ item: ClipItem) -> String {
        let text = item.title.isEmpty ? item.preview : item.title
        let collapsed = text.replacingOccurrences(of: "\n", with: " ")
        guard collapsed.count > summaryWidth else { return collapsed }
        return String(collapsed.prefix(summaryWidth - 1)) + "…"
    }

    /// The CLI's JSON shape: stable key order and ISO-8601 dates, so output can
    /// be diffed between runs and parsed by anything.
    static func encodePretty(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(value)
    }

    /// Where the CLI reads the store from.
    ///
    /// `GANCHO_STORE_DIR` overrides the app's container — it exists so tests
    /// and a sandboxed CLI can point somewhere writable. Honored only when it
    /// is non-empty: an exported-but-blank variable is a shell accident, and
    /// treating it as a path would send the CLI to the filesystem root instead
    /// of the user's history.
    static func storeDirectory(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["GANCHO_STORE_DIR"],
            !override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return SharedStorageLocation.macAppStoreDirectory
    }
}
