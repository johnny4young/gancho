import Foundation
import GanchoKit

/// What a row says about a clip: the content in its native form, then a quiet
/// description. Built only from what the row already holds (kind, title, the
/// stored preview, image header facts); nothing is fetched or guessed.
public struct ClipRowContent: Equatable, Sendable {
    /// How much of the clip a row may show.
    public enum Masking: Sendable {
        case none
        /// A protected clip: its stored mask and kind, never its content.
        case storedMask
        /// Private Mode: the kind's glyph and nothing else.
        case hidden

        /// Hidden previews win over a clip's own protection.
        public static func `for`(_ item: ClipItem, previewsHidden: Bool) -> Masking {
            if previewsHidden { return .hidden }
            return ClipSafePresentation.requiresMasking(item) ? .storedMask : .none
        }
    }

    public enum Headline: Equatable, Sendable {
        case text(String)
        /// A literal value: a colour, an identifier, a masked token.
        case value(String)
        case code(String)
        /// Host first, then what follows it; no scheme and no `www.`.
        case link(host: String, path: String?)
        /// An untitled image has no name of its own.
        case kindName(ClipContentKind)
    }

    public enum Detail: Equatable, Sendable {
        case verbatim(String)
        case lines(Int)
        case kindName(ClipContentKind)
    }

    /// Capture stores at most this much of a text clip; a shorter preview is
    /// the whole clip, so only then can its lines be counted.
    public static let storedPreviewLimit = 120

    public let headline: Headline
    public let details: [Detail]

    public init(item: ClipItem, masking: Masking = .none) {
        switch masking {
        case .hidden:
            headline = .text(ClipSafePresentation.masked)
            details = []
        case .storedMask:
            headline = .value(ClipSafePresentation.maskedTail(for: item))
            details = [.kindName(item.kind)]
        case .none:
            (headline, details) = Self.plain(item)
        }
    }

    private static func plain(_ item: ClipItem) -> (Headline, [Detail]) {
        let lines = item.preview.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let first = lines.first ?? ""
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let titled: [Detail] = title.isEmpty ? [] : [.verbatim(title)]
        let counted = lineCount(of: item.preview).map { [Detail.lines($0)] } ?? []

        switch item.kind {
        case .url:
            guard let link = ClipLinkParts(text: item.preview) else {
                return (.text(first), titled)
            }
            return (.link(host: link.host, path: link.path), titled)
        case .color:
            return (.value(first), titled + colorDetail(for: first))
        case .code, .json:
            return (.code(first), titled + counted)
        case .image:
            let facts = imageFacts(for: item).map(Detail.verbatim)
            return (title.isEmpty ? .kindName(.image) : .text(title), facts)
        case .fileReference:
            return (
                .text(first), titled + [fileType(of: first)].compactMap(\.self).map(Detail.verbatim)
            )
        case .text, .richText:
            let next = title.isEmpty ? lines.dropFirst().first : lines.first
            return (
                .text(title.isEmpty ? first : title),
                [next].compactMap(\.self).map(Detail.verbatim) + counted
            )
        case .uuid:
            return (.value(first), title.isEmpty ? [.kindName(item.kind)] : titled)
        default:
            return (.text(first), title.isEmpty ? [.kindName(item.kind)] : titled)
        }
    }

    /// The number of lines, from two up, when the preview is the whole clip.
    static func lineCount(of preview: String) -> Int? {
        guard preview.count < storedPreviewLimit else { return nil }
        let count = preview.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        return count > 1 ? count : nil
    }

    /// "rgb 255 107 74" under a hex value; the hex under any other notation.
    static func colorDetail(for text: String) -> [Detail] {
        guard let value = ColorValue.parse(text) else { return [] }
        guard text.hasPrefix("#") else { return [.verbatim(value.hex)] }
        return [.verbatim("rgb \(value.red) \(value.green) \(value.blue)")]
    }

    /// "PNG", "2400 × 1350", "1.8 MB": whichever of them the clip recorded.
    static func imageFacts(for item: ClipItem) -> [String] {
        var facts: [String] = []
        if let info = item.imageInfo {
            facts += [info.formatName, "\(info.width) × \(info.height)"].compactMap(\.self)
        }
        // Capture stores the byte size as the image's preview: "Image (1.8 MB)".
        let preview = ByteSize.humanizedPreview(item.preview)
        if preview.hasPrefix("Image ("), preview.hasSuffix(")") {
            // Never split on ",": it is the decimal separator in many locales.
            let size = preview.dropFirst("Image (".count).dropLast()
                .trimmingCharacters(in: .whitespaces)
            if !size.isEmpty { facts.append(size) }
        }
        return facts
    }

    /// The upper-cased extension of a single file name ("PDF"); nil for a
    /// name without one or a list of names.
    static func fileType(of name: String) -> String? {
        guard !name.contains(", ") else { return nil }
        let ext = (name as NSString).pathExtension
        return ext.isEmpty || ext.count > 8 ? nil : ext.uppercased()
    }
}

extension ClipRowContent.Headline {
    /// For surfaces that float over other apps: a link's query and fragment can carry tokens.
    public var withoutLinkQuery: Self {
        guard case .link(let host, let path) = self, let path else { return self }
        let kept = path.prefix { $0 != "?" && $0 != "#" }
        return .link(host: host, path: kept.isEmpty || kept == "/" ? nil : String(kept))
    }
}
