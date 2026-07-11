import Testing

@testable import GanchoKit

@Suite("Paste transforms — pure, never mutate the stored clip")
struct PasteTransformTests {
    @Test("Each transform behaves")
    func transforms() {
        #expect(PasteTransform.lowercase.apply(to: "MiXeD") == "mixed")
        #expect(PasteTransform.uppercase.apply(to: "MiXeD") == "MIXED")
        #expect(PasteTransform.trimmed.apply(to: "  body  \n") == "body")
        #expect(
            PasteTransform.singleLine.apply(to: "line one\n  line two\n\nline three")
                == "line one line two line three")
        #expect(PasteTransform.plainText.apply(to: "as-is") == "as-is")
    }

    @Test("Title Case handles unicode and stays locale-independent")
    func titleCase() {
        #expect(
            PasteTransform.titleCase.apply(to: "ñandú viaja al ártico") == "Ñandú Viaja Al Ártico")
        #expect(PasteTransform.titleCase.apply(to: "").isEmpty)
    }

    @Test("Collapse spaces squeezes runs but preserves line structure")
    func collapseSpaces() {
        #expect(
            PasteTransform.collapseSpaces.apply(to: "a  b\tc\n\n  d   e ")
                == "a b c\n\nd e")
        #expect(
            PasteTransform.collapseSpaces.apply(to: "a  b\r\n\r\n d\t e ")
                == "a b\n\nd e")
        #expect(PasteTransform.collapseSpaces.apply(to: "a  b\u{2028} c") == "a b\nc")
        #expect(PasteTransform.collapseSpaces.apply(to: "").isEmpty)
    }

    @Test("Sort lines is plain lexicographic, empty lines first")
    func sortLines() {
        #expect(
            PasteTransform.sortLines.apply(to: "beta\n\nalpha\ncharlie")
                == "\nalpha\nbeta\ncharlie")
        #expect(PasteTransform.sortLines.apply(to: "beta\r\nalpha\r\n") == "\nalpha\nbeta")
    }

    @Test("Dedupe lines keeps the first occurrence, preserves order")
    func dedupeLines() {
        #expect(
            PasteTransform.dedupeLines.apply(to: "b\na\nb\n\nc\n\na")
                == "b\na\n\nc")
        #expect(PasteTransform.dedupeLines.apply(to: "a\r\nb\r\na") == "a\nb")
    }

    @Test("URL encode covers reserved characters; decode round-trips")
    func urlEncodeDecode() {
        let raw = "a b&c=d/ñ?"
        let encoded = PasteTransform.urlEncode.apply(to: raw)
        #expect(encoded == "a%20b%26c%3Dd%2F%C3%B1%3F")
        #expect(PasteTransform.urlDecode.apply(to: encoded) == raw)
        // Malformed sequences pass through unchanged instead of pasting nothing.
        #expect(PasteTransform.urlDecode.apply(to: "100%ZZ") == "100%ZZ")
    }

    @Test("SHA-256 matches the published test vector")
    func sha256() {
        #expect(
            PasteTransform.sha256Hex.apply(to: "abc")
                == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(
            PasteTransform.sha256Hex.apply(to: "")
                == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }
}
