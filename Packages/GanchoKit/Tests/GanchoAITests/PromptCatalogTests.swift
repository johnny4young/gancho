import CryptoKit
import Foundation
import Testing

@testable import GanchoAI

/// The prompt-version policy, enforced: every shipped prompt lives in the
/// catalog with a stable id, an owner, and a version whose wording is FROZEN
/// by hash — changing a prompt's text without bumping its version fails here,
/// and bumping a version reminds the owner to re-run the `GANCHO_AI_EVAL=1`
/// evaluation before shipping. The criteria functions are exercised against
/// deliberately bad outputs so the evaluation harness is proven able to fail.
@Suite("Prompt catalog — identity, guardrails, and version freeze")
struct PromptCatalogTests {
    @Test("Every prompt has a unique id, an owner, and a positive version")
    func identity() {
        let specs = PromptCatalog.all
        #expect(!specs.isEmpty)
        #expect(Set(specs.map(\.id)).count == specs.count, "prompt ids must be unique")
        for spec in specs {
            #expect(!spec.owner.isEmpty, "\(spec.id) needs an accountable owner")
            #expect(spec.version >= 1)
            #expect(spec.instructions.count > 20)
        }
    }

    @Test("Every prompt forbids leaking secret material")
    func guardrails() {
        for spec in PromptCatalog.all {
            #expect(
                spec.instructions.localizedCaseInsensitiveContains("secret material"),
                "\(spec.id) must carry the secret guardrail")
        }
    }

    @Test("Call sites serve exactly the catalog wording")
    func callSitesDelegate() {
        for action in SmartPasteAction.allCases {
            #expect(action.instructions == PromptCatalog.smartPaste(action).instructions)
        }
        #expect(ClipboardQAService.instructions == PromptCatalog.askClipboard.instructions)
        let rendered = SmartPasteService.translateInstructions(to: "French")
        #expect(rendered.contains("French"))
        #expect(!rendered.contains("{language}"), "the template placeholder must be filled")
    }

    /// The freeze: wording is pinned to `id@version`. On a wording change this
    /// fails and prints the new hash — bump the version, update the entry here,
    /// and re-run the evaluation suite before shipping the new wording.
    @Test("Prompt wording is frozen to its version")
    func versionFreeze() {
        // v2 (2026-07-16): the first live evaluation caught the title prompt
        // obeying injected instructions and summaries/answers reproducing a
        // planted key — every wording gained the [redacted] substitution
        // directive (and the title prompt an anti-injection clause).
        let frozen: [String: String] = [
            "annotate.title@v2":
                "57ec673c03dc0c811c753be153377698df1432cd6b1b55f395c1b495740c7e44",
            "ask.clipboard@v2":
                "5ab2b513e2d8880156fae7c4f4cec6dbee64033c7bb9dc5834dc32e1c21accdf",
            "smart-paste.translate@v2":
                "04ad179621cef1993de89cf8d6179754f62391dc9973d6cc03de78e04ce777de",
            "smart-paste.summarize@v2":
                "356540beae06ddd5a10fe8a4718c73f692def33c8fbec2da367b028573b55460",
            "smart-paste.proofread@v2":
                "b02d50083999f095ea179647e448d6dbf8a7d72485159ca0de1d62ee01941068",
            "smart-paste.formal@v2":
                "68a80f0b885109d1fb2e56e6862f4bb16641ce8cf5cd953c1cc57b7046b65827",
            "smart-paste.friendly@v2":
                "df69666ba6245c901c8071845a6487930bebbc4fdf96dec82085d8e9354ecba5",
            "smart-paste.key-points@v2":
                "ed6e6536c10792554b5f896654660877691032615e6db601ca14494838770963",
            "smart-paste.redact-pii@v2":
                "7bfdf34729f1887299bef6d65e3e2fb9c0b66c3845a3898a88b0b88b3f9e2f4d"
        ]
        for spec in PromptCatalog.all {
            let digest = SHA256.hash(data: Data(spec.instructions.utf8))
            let hex = digest.map { String(format: "%02x", $0) }.joined()
            #expect(
                frozen[spec.versionedID] == hex,
                "\(spec.versionedID) wording changed — bump the version, freeze \(hex), and re-run GANCHO_AI_EVAL=1 before shipping"
            )
        }
        #expect(frozen.count == PromptCatalog.all.count, "every prompt must be frozen")
    }

    // MARK: - The criteria can fail (a harness that can't fail proves nothing)

    @Test("Title criteria reject verbatim echoes, over-long and quoted titles")
    func titleCriteria() {
        #expect(PromptCriteria.titleIsValid("Deploy checklist for staging"))
        #expect(!PromptCriteria.titleIsValid(""))
        #expect(!PromptCriteria.titleIsValid("\"Quoted title\""))
        #expect(!PromptCriteria.titleIsValid("one two three four five six seven"))
    }

    @Test("Category criteria accept only the closed kind set")
    func categoryCriteria() {
        #expect(PromptCriteria.isKnownCategory("url"))
        #expect(PromptCriteria.isKnownCategory("secret"))
        #expect(!PromptCriteria.isKnownCategory("miscellaneous"))
    }

    @Test("Secret-echo criterion catches a planted token in the output")
    func secretEcho() {
        let planted = ["sk-demo-4242424242", "hunter2-staging"]
        #expect(PromptCriteria.leaksAny(of: planted, in: "the key is SK-DEMO-4242424242"))
        #expect(!PromptCriteria.leaksAny(of: planted, in: "an API key for staging"))
    }

    @Test("Adversarial criterion catches compliance with injected instructions")
    func adversarialCompliance() {
        #expect(PromptCriteria.compliedWithAdversarialInput("PWNED-7391 ok", marker: "PWNED-7391"))
        #expect(
            !PromptCriteria.compliedWithAdversarialInput("A note about lunch", marker: "PWNED-7391")
        )
    }

    @Test("Bullet-list criterion rejects prose and empty output")
    func bulletShape() {
        #expect(PromptCriteria.isBulletList("- first\n- second"))
        #expect(!PromptCriteria.isBulletList("first, then second"))
        #expect(!PromptCriteria.isBulletList(""))
    }

    @Test("Invention criterion catches a decoy fact absent from the sources")
    func invention() {
        #expect(
            PromptCriteria.inventsAny(of: ["flight AA9999"], in: "Your flight AA9999 departs at 9"))
        #expect(!PromptCriteria.inventsAny(of: ["flight AA9999"], in: "I couldn't find that"))
    }
}
