import Foundation
import Testing

@testable import GanchoKit

/// The client-side twin of the SQL evaluation, used only without a durable
/// store — so it must agree with the store on kind, app, pin and each mode.
@Suite("Saved filter rule — client-side matching")
struct SmartCollectionRuleMatchingTests {
    private let link = ClipItem(
        kind: .url, preview: "https://Example.test/Docs", sourceAppBundleID: "a")
    private let note = ClipItem(
        preview: "Daily notes for today", sourceAppBundleID: "b", isPinned: true)

    @Test func kindAppAndPin() {
        #expect(SmartCollectionRule(name: "", kinds: [.url]).matches(link))
        #expect(!SmartCollectionRule(name: "", kinds: [.url]).matches(note))
        #expect(SmartCollectionRule(name: "", sourceAppBundleID: "b").matches(note))
        #expect(!SmartCollectionRule(name: "", sourceAppBundleID: "b").matches(link))
        #expect(SmartCollectionRule(name: "", pinnedOnly: true).matches(note))
        #expect(!SmartCollectionRule(name: "", pinnedOnly: true).matches(link))
        #expect(SmartCollectionRule(name: "").matches(link), "no predicates matches everything")
    }

    @Test func fuzzyIsPerTokenPrefixCaseInsensitive() {
        #expect(SmartCollectionRule(name: "", textContains: "dai tod").matches(note))
        #expect(!SmartCollectionRule(name: "", textContains: "aily").matches(note))
        #expect(SmartCollectionRule(name: "", textContains: "  ").matches(note), "blank = no text")
    }

    @Test func exactIsThePhraseInOrder() {
        let exact = SmartCollectionRule(name: "", textContains: "notes for", searchMode: .exact)
        #expect(exact.matches(note))
        #expect(
            !SmartCollectionRule(name: "", textContains: "for notes", searchMode: .exact).matches(
                note))
    }

    @Test func regexRunsCaseInsensitiveAndInvalidMatchesNothing() {
        #expect(
            SmartCollectionRule(name: "", textContains: "^https://example", searchMode: .regex)
                .matches(link))
        #expect(!SmartCollectionRule(name: "", textContains: "(", searchMode: .regex).matches(link))
    }
}
