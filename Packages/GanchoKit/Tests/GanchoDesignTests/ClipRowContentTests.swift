import Foundation
import GanchoKit
import Testing

@testable import GanchoDesign

@Suite("ClipRowContent — a row shows the clip itself, then describes it")
struct ClipRowContentTests {
    private func row(
        _ kind: ClipContentKind, _ preview: String, title: String = "",
        imageInfo: ClipImageInfo? = nil, masking: ClipRowContent.Masking = .none
    ) -> ClipRowContent {
        ClipRowContent(
            item: ClipItem(
                kind: kind, title: title, preview: preview, contentHash: "h", imageInfo: imageInfo),
            masking: masking)
    }

    @Test("A link leads with its host; scheme and www. are dropped; the title describes it")
    func link() {
        let titled = row(.url, "https://www.gancho.app/launch/press-kit", title: "Press kit")
        #expect(titled.headline == .link(host: "gancho.app", path: "/launch/press-kit"))
        #expect(titled.details == [.verbatim("Press kit")])

        let bare = row(.url, "https://example.com/")
        #expect(bare.headline == .link(host: "example.com", path: nil))
        #expect(bare.details.isEmpty, "no title: nothing is invented")
        #expect(row(.url, "not a url").headline == .text("not a url"))
    }

    @Test("A colour is its value; the description is the other notation")
    func colour() {
        let hex = row(.color, "#FF6B4A", title: "Launch coral")
        #expect(hex.headline == .value("#FF6B4A"))
        #expect(hex.details == [.verbatim("Launch coral"), .verbatim("rgb 255 107 74")])
        #expect(row(.color, "rgb(255, 107, 74)").details == [.verbatim("#FF6B4A")])
        #expect(row(.color, "not a colour").details.isEmpty)
    }

    @Test("Code is its first line; lines are counted only when the preview is the whole clip")
    func code() {
        let short = row(.code, "let launch = Date.now\nprint(launch)\nexit(0)")
        #expect(short.headline == .code("let launch = Date.now"))
        #expect(short.details == [.lines(3)])
        #expect(row(.code, "let x = 1").details.isEmpty, "one line needs no count")

        let cut = String(repeating: "a = 1\n", count: 40)
        let truncated = row(.code, String(cut.prefix(ClipRowContent.storedPreviewLimit)))
        #expect(truncated.details.isEmpty, "a truncated preview cannot be counted")
    }

    @Test("An image names itself by title, with the facts its header recorded")
    func image() {
        let info = ClipImageInfo(width: 2400, height: 1350, typeIdentifier: "public.png")
        let titled = row(.image, "Image (1.8 MB)", title: "launch-hero", imageInfo: info)
        #expect(titled.headline == .text("launch-hero"))
        #expect(
            titled.details == [.verbatim("PNG"), .verbatim("2400 × 1350"), .verbatim("1.8 MB")])

        let untitled = row(.image, "Image (public.png, 2048 bytes)")
        #expect(untitled.headline == .kindName(.image))
        #expect(untitled.details == [.verbatim("2 KB")])
        #expect(
            row(.image, "Image (1,8 MB)").details == [.verbatim("1,8 MB")],
            "a decimal comma is not a separator")
    }

    @Test("Text leads with its title or first line, then the next line and a count")
    func text() {
        let titled = row(.text, "Ship the onboarding fix\nThen the changelog", title: "Checklist")
        #expect(titled.headline == .text("Checklist"))
        #expect(titled.details == [.verbatim("Ship the onboarding fix"), .lines(2)])

        let untitled = row(.text, "First\n\nSecond")
        #expect(untitled.headline == .text("First"))
        #expect(untitled.details == [.verbatim("Second"), .lines(3)])
        #expect(row(.text, "One line").details.isEmpty)
    }

    @Test("A single file names its type; a list of files does not guess one")
    func file() {
        #expect(row(.fileReference, "Launch-plan.pdf").details == [.verbatim("PDF")])
        #expect(row(.fileReference, "a.pdf, b.png").details.isEmpty)
        #expect(row(.fileReference, "Makefile").details.isEmpty)
    }

    @Test(
        "A value kind is its value, described by its title or else its kind",
        arguments: [ClipContentKind.email, .phoneNumber, .address, .date, .trackingNumber])
    func values(_ kind: ClipContentKind) {
        #expect(row(kind, "value").headline == .text("value"))
        #expect(row(kind, "value").details == [.kindName(kind)])
        #expect(row(kind, "value", title: "Named").details == [.verbatim("Named")])
    }

    @Test("A protected clip shows its stored mask and kind, never its title or text")
    func storedMask() {
        let masked = row(.secret, "●●●● 4Q2v", title: "Private title", masking: .storedMask)
        #expect(masked.headline == .value("●●●● 4Q2v"))
        #expect(masked.details == [.kindName(.secret)])

        let unmasked = row(.secret, "sk_live_plaintext", masking: .storedMask)
        #expect(unmasked.headline == .value(ClipSafePresentation.masked), "not mask-shaped")
    }

    @Test("Private Mode shows three dots and no description", arguments: ClipContentKind.allCases)
    func hidden(_ kind: ClipContentKind) {
        let hidden = row(kind, "https://gancho.app/private", title: "Private", masking: .hidden)
        #expect(hidden.headline == .text(ClipSafePresentation.masked))
        #expect(hidden.details.isEmpty)
    }

    @Test("Hidden previews mask every clip; otherwise only protected clips are masked")
    func maskingFor() {
        let plain = ClipItem(kind: .text, title: "", preview: "hello", contentHash: "a")
        let secret = ClipItem(kind: .secret, title: "", preview: "●●●● 4Q2v", contentHash: "b")
        #expect(ClipRowContent.Masking.for(plain, previewsHidden: true) == .hidden)
        #expect(ClipRowContent.Masking.for(secret, previewsHidden: true) == .hidden)
        #expect(ClipRowContent.Masking.for(secret, previewsHidden: false) == .storedMask)
        #expect(ClipRowContent.Masking.for(plain, previewsHidden: false) == .none)
    }

    @Test("Floating surfaces drop a link's query and fragment but keep its path")
    func withoutLinkQuery() {
        let reset = row(.url, "https://www.gancho.app/reset/pass?token=abc123#step=2")
        #expect(reset.headline.withoutLinkQuery == .link(host: "gancho.app", path: "/reset/pass"))
        let fragment = row(.url, "https://auth.example.com/cb#access_token=xyz")
        #expect(fragment.headline.withoutLinkQuery == .link(host: "auth.example.com", path: "/cb"))
        let bare = row(.url, "https://example.com/?q=secret")
        #expect(bare.headline.withoutLinkQuery == .link(host: "example.com", path: nil))
        #expect(
            row(.url, "https://example.com").headline.withoutLinkQuery
                == .link(host: "example.com", path: nil))
        #expect(row(.text, "a?b").headline.withoutLinkQuery == .text("a?b"))
    }

    @Test("The selected row's key is Return; other rows keep ⌘1–⌘9")
    func shortcutKey() {
        #expect(ClipShortcutBadge.key(number: 3, isSelected: false) == .number(3))
        #expect(ClipShortcutBadge.key(number: 3, isSelected: true) == .returnKey)
        #expect(ClipShortcutBadge.key(number: nil, isSelected: true) == .returnKey)
        #expect(ClipShortcutBadge.key(number: 12, isSelected: true) == .returnKey)
        #expect(ClipShortcutBadge.key(number: 12, isSelected: false) == nil)
        #expect(ClipShortcutBadge.key(number: nil, isSelected: false) == nil)
    }

    @Test("Tiles use outline glyphs")
    func tileGlyphs() {
        #expect(ClipTile.symbolName(for: .secret) == "lock")
        #expect(ClipTile.symbolName(for: .url) == ClipContentKind.url.symbolName)
        #expect(
            ClipContentKind.allCases.allSatisfy {
                !ClipTile.symbolName(for: $0).hasSuffix(".fill")
            })
    }
}
