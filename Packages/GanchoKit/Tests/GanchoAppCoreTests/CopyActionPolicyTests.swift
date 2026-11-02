import ClipboardCore
import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Copy-time action HUD policy")
struct CopyActionPolicyTests {
    private let on = CopyActionSwitches(isEnabled: true)

    private func action(
        _ text: String, kind: ClipContentKind, switches: CopyActionSwitches? = nil,
        sensitive: Bool = false, privateMode: Bool = false, sharing: Bool = false,
        isNew: Bool = true
    ) -> CopyAction? {
        CopyActionPolicy.action(
            for: ClipItem(kind: kind, contentHash: text, isSensitive: sensitive), isNew: isNew,
            text: text,
            switches: switches ?? on, privateMode: privateMode, sharingScreen: sharing)
    }

    @Test("Colors, web links and codes get their action")
    func kinds() throws {
        #expect(
            action("#008080", kind: .color) == .color(try #require(ColorValue.parse("#008080"))))
        #expect(
            action(" https://gancho.app/docs ", kind: .url)
                == .link(try #require(URL(string: "https://gancho.app/docs"))))
        #expect(action("482 913", kind: .text) == .oneTimeCode)
        #expect(action("4829", kind: .phoneNumber) == .oneTimeCode)
    }

    @Test("Plain text, other schemes and an unparseable color get nothing")
    func nothingToOffer() {
        #expect(action("Ana Restrepo", kind: .text) == nil)
        #expect(action("file:///etc/hosts", kind: .url) == nil)
        #expect(action("mailto:ana@example.com", kind: .url) == nil)
        #expect(action("ftp://gancho.app/files", kind: .url) == nil)
        #expect(action("javascript://gancho.app/%0Aalert(1)", kind: .url) == nil)
        #expect(action("not a color", kind: .color) == nil)
    }

    @Test("Off, a kind switched off, private, sharing or sensitive: no HUD")
    func suppressed() {
        #expect(action("#008080", kind: .color, switches: CopyActionSwitches()) == nil)
        #expect(
            action(
                "#008080", kind: .color,
                switches: CopyActionSwitches(isEnabled: true, colors: false))
                == nil)
        #expect(
            action(
                "https://gancho.app", kind: .url,
                switches: CopyActionSwitches(isEnabled: true, links: false)) == nil)
        #expect(
            action(
                "482913", kind: .text,
                switches: CopyActionSwitches(isEnabled: true, oneTimeCodes: false)) == nil)
        #expect(action("#008080", kind: .color, privateMode: true) == nil)
        #expect(action("#008080", kind: .color, sharing: true) == nil)
        #expect(action("482913", kind: .text, sensitive: true) == nil)
        #expect(action("4111 1111", kind: .creditCard) == nil, "a masked kind")
        #expect(action("482913", kind: .text, isNew: false) == nil, "a recopied code")
        #expect(action("#008080", kind: .color, isNew: false) != nil, "a recopied color")
    }

    @Test("A code is the whole text: 4–8 digits, or two groups of 3–4")
    func oneTimeCodes() {
        for code in ["4829", "482913", "48291375", "482 913", "4829-1375", " 482913\n"] {
            #expect(OneTimeCodeDetector.matches(code), "\(code)")
        }
        for other in [
            "482", "482913751", "48 2913", "482  913", "482-913-751", "482913a", "Code 482913",
            "4829 13755", "", "４８２９１３"
        ] {
            #expect(!OneTimeCodeDetector.matches(other), "\(other)")
        }
    }
}
