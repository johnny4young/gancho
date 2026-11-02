import GanchoKit
import SwiftUI

#if canImport(AppKit)
    import AppKit
#endif

extension GanchoTokens.Syntax {
    /// (light, dark) for a snippet placeholder: fields amber, clipboard blue,
    /// dates purple, the cursor grey.
    static func triples(
        for placeholder: SnippetTemplate.Placeholder
    ) -> (light: (Int, Int, Int), dark: (Int, Int, Int)) {
        switch placeholder {
        case .field: triples(for: GanchoSyntax.TokenKind.placeholder)
        case .clipboard: ((0x1F, 0x5F, 0xA8), (0x5A, 0xC8, 0xFA))
        case .date: ((0x3D, 0x3B, 0xB0), (0xB0, 0xAE, 0xF5))
        case .cursor: ((0x5F, 0x5F, 0x64), (0xA1, 0xA1, 0xA6))
        }
    }

    public static func color(for placeholder: SnippetTemplate.Placeholder) -> Color {
        let t = triples(for: placeholder)
        return syntaxDynamicColor(light: t.light, dark: t.dark)
    }

    #if canImport(AppKit)
        public static func nsColor(for placeholder: SnippetTemplate.Placeholder) -> NSColor {
            let t = triples(for: placeholder)
            return syntaxDynamicNSColor(light: t.light, dark: t.dark)
        }
    #endif
}
