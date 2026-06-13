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
}
