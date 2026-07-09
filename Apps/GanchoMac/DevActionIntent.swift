import AppIntents
import GanchoAI

/// Every dev action, exposed to Shortcuts/Spotlight/Siri through ONE intent
/// that calls the exact same `DevActions.run` the UI uses — no logic forks.
struct DevActionIntent: AppIntent {
    static let title: LocalizedStringResource = "Transform Text"
    static let description = IntentDescription(
        // swiftlint:disable:next line_length
        "Runs a Gancho developer action (decode JWT, pretty-print JSON, parse URL, convert color…) on the given text. Fully offline."
    )

    @Parameter(title: "Action")
    var action: DevActionChoice

    @Parameter(title: "Text")
    var text: String

    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let output = try DevActions.run(action.id, on: text)
        return .result(value: output)
    }
}

/// AppEnum bridge over the action catalog.
enum DevActionChoice: String, AppEnum {
    case decodeJWT, jsonPretty, jsonMinify, base64Encode, base64Decode
    case parseURL, convertColor, uuidFormats
    case sha256Hex, sha1Hex, md5Hex, urlEncode, urlDecode, caseConvert
    case epochToDate, dateToEpoch, sortLines, dedupeLines, reverseLines
    case countStats, htmlEntityEncode, htmlEntityDecode, slugify
    case numberBaseConvert, jsonEscape, jsonUnescape

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Dev Action"
    static let caseDisplayRepresentations: [DevActionChoice: DisplayRepresentation] = [
        .decodeJWT: "Decode JWT",
        .jsonPretty: "Pretty-print JSON",
        .jsonMinify: "Minify JSON",
        .base64Encode: "Base64 encode",
        .base64Decode: "Base64 decode",
        .parseURL: "Parse URL",
        .convertColor: "Convert color",
        .uuidFormats: "UUID formats",
        .sha256Hex: "SHA-256 hash",
        .sha1Hex: "SHA-1 hash",
        .md5Hex: "MD5 hash",
        .urlEncode: "URL encode",
        .urlDecode: "URL decode",
        .caseConvert: "Convert case",
        .epochToDate: "Epoch to date",
        .dateToEpoch: "Date to epoch",
        .sortLines: "Sort lines",
        .dedupeLines: "Dedupe lines",
        .reverseLines: "Reverse lines",
        .countStats: "Count stats",
        .htmlEntityEncode: "HTML-entity encode",
        .htmlEntityDecode: "HTML-entity decode",
        .slugify: "Slugify",
        .numberBaseConvert: "Convert number base",
        .jsonEscape: "JSON-escape string",
        .jsonUnescape: "JSON-unescape string"
    ]

    var id: DevActions.ActionID {
        DevActions.ActionID(rawValue: rawValue) ?? .jsonPretty
    }
}
