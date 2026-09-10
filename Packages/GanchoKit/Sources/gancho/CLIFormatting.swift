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
    /// preview, with anything that could break the row flattened to a space,
    /// and truncated with an ellipsis.
    ///
    /// The row is tab-separated (`id \t kind \t summary`) and clipboard text is
    /// arbitrary, so flattening only `\n` was not enough:
    /// - a bare CR returns the cursor to column 0 and overwrites the id and
    ///   kind already printed. The previous `replacingOccurrences(of: "\n")`
    ///   did not merely miss that case, it CREATED it: given `\r\n` it replaced
    ///   the LF and left the CR behind, so Windows-origin text was the worst
    ///   input rather than the safest;
    /// - `isNewline` alone still misses the other C0/C1 controls: a TAB opens a
    ///   phantom column, and an ESC lets a sequence copied out of a terminal
    ///   run against the user's terminal.
    ///
    /// Tested per grapheme cluster against the `control` general category, not
    /// `CharacterSet.controlCharacters` — that set is Cc *and* Cf, and Cf holds
    /// the zero-width joiner, so it would erase every joined emoji. `\r\n` is a
    /// single `Character` and collapses to a single space.
    ///
    /// The result never exceeds ``summaryWidth`` INCLUDING the ellipsis — the
    /// ellipsis replaces a character rather than being appended past the limit.
    static func oneLine(_ item: ClipItem) -> String {
        let collapsed = flattened(item.title.isEmpty ? item.preview : item.title)
        guard collapsed.count > summaryWidth else { return collapsed }
        return String(collapsed.prefix(summaryWidth - 1)) + "…"
    }

    /// One printable row: every character that could move the cursor, open a
    /// column, or start an escape sequence replaced by a space.
    ///
    /// The single place that decision lives. Clip summaries were the first
    /// caller, but a board name, a store path and an echoed argument all land
    /// in the same kind of tab-separated or labelled row, and each of them can
    /// carry text the CLI never chose: board names are trimmed only at the
    /// EDGES, so an interior CR survives into the store and out to stdout.
    ///
    /// Length is deliberately not bounded here. ``oneLine(_:)`` truncates
    /// because a clip preview is unbounded prose; a board name or a path is
    /// not, and silently cutting one would hide the very thing the row exists
    /// to show.
    static func flattened(_ text: String) -> String {
        String(text.map { rowSafe($0) ? $0 : " " })
    }

    /// One tab-separated row: each column flattened, then joined with a
    /// delimiter the CLI owns.
    ///
    /// The order matters and is the whole point. Flattening the ASSEMBLED row
    /// also eats the separators that were already placed, turning documented
    /// tab-separated output into space-separated prose that nothing can parse.
    /// Sanitize the fields, then delimit — never the reverse.
    static func row(_ columns: [String]) -> String {
        columns.map(flattened).joined(separator: "\t")
    }

    /// One diagnostic line for stderr: flattened, with the newline it owns.
    ///
    /// Lives here, beside the row builder, so the stderr funnel's formatting is
    /// directly testable. Writing to a `FileHandle` is not, and a funnel whose
    /// only proof is "the code says so" is one refactor away from silently
    /// passing raw control characters through again.
    static func diagnostic(_ message: String) -> String {
        flattened(message) + "\n"
    }

    /// False for anything that would move the cursor, open a column, or start
    /// an escape sequence once printed.
    ///
    /// Matched per grapheme cluster on the `control` general category (Cc)
    /// rather than `CharacterSet.controlCharacters`, which is Cc *and* Cf —
    /// Cf holds the zero-width joiner, so the broader set collapses a joined
    /// family emoji into spaces. `isNewline` is needed alongside it because
    /// LINE SEPARATOR and PARAGRAPH SEPARATOR are neither Cc nor Cf.
    private static func rowSafe(_ character: Character) -> Bool {
        !character.isNewline
            && !character.unicodeScalars.contains { $0.properties.generalCategory == .control }
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
    /// `URL(fileURLWithPath: "")` resolves against the process's CURRENT
    /// WORKING DIRECTORY — not the filesystem root — so honoring it would read
    /// a store from wherever the user happened to run `gancho` and report an
    /// empty history.
    ///
    /// The emptiness check trims but the lookup does not, deliberately: a path
    /// may legitimately end in a space, so only an ENTIRELY whitespace value
    /// counts as unset.
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
