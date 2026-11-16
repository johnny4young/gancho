import Foundation
import GanchoAI
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Transform catalog and pipeline")
struct TransformCatalogTests {
    @Test("The clip's own actions come first, then text, recipes and Smart paste")
    func groupOrder() {
        let groups = TransformCatalog.groups(
            kind: .code, includesRecipes: true, smartPaste: true, modelAvailable: true,
            translationCodes: ["es"])

        #expect(groups.map(\.kind) == [.clipKind(.code), .text, .recipes, .smartPaste])
        #expect(groups[1].rows.contains(.step(.text(.plainText))) == false)
        #expect(groups[3].rows.last == .translate("es"))
    }

    @Test("Without the model only Redact PII stays in Smart paste; no rows, no group")
    func modelGate() {
        let groups = TransformCatalog.groups(
            kind: .text, includesRecipes: false, smartPaste: true, modelAvailable: false,
            translationCodes: [])
        #expect(groups.last?.rows == [.smartPaste(.redactPII)])
        #expect(!groups.contains { $0.kind == .recipes })

        let off = TransformCatalog.groups(
            kind: .color, includesRecipes: false, smartPaste: false, modelAvailable: true,
            translationCodes: [])
        #expect(!off.contains { $0.kind == .smartPaste })
    }

    @Test("Describe the change and saved prompts lead Smart paste, only when offered")
    func describeRows() {
        let groups = TransformCatalog.groups(
            kind: .text, includesRecipes: false, smartPaste: true, modelAvailable: true,
            translationCodes: [], describeChange: true, savedPrompts: ["Make it formal"])
        #expect(
            Array(groups.last?.rows.prefix(2) ?? []) == [
                .describeChange, .savedPrompt("Make it formal")
            ])

        let noModel = TransformCatalog.groups(
            kind: .text, includesRecipes: false, smartPaste: true, modelAvailable: false,
            translationCodes: [], describeChange: false, savedPrompts: ["Make it formal"])
        #expect(noModel.last?.rows == [.smartPaste(.redactPII)])
    }

    @Test("Filtering matches every word across groups and drops empty groups")
    func filtering() {
        let groups = TransformCatalog.groups(
            kind: .code, includesRecipes: true, smartPaste: false, modelAvailable: false,
            translationCodes: [])
        let title: (TransformRow) -> String = { row in
            if case .step(let step) = row { return step.title }
            return "Text recipes"
        }

        let base = TransformCatalog.matching(groups, query: "base64 ENC", title: title)
        #expect(base.flatMap(\.rows) == [.step(.dev(.base64Encode))])
        #expect(TransformCatalog.matching(groups, query: "zzz", title: title).isEmpty)
        #expect(TransformCatalog.matching(groups, query: "  ", title: title) == groups)
    }

    @Test("The clip group lists the dock's verbs in panel order, then Markdown and Delete")
    func clipVerbs() {
        let link = TransformCatalog.clipGroup(
            dockIDs: [
                "preview-paste", "preview-paste-plain", "preview-pin", "preview-board",
                "preview-stack", "preview-context"
            ], markdownLink: true)
        #expect(link.kind == .clip)
        #expect(
            link.rows == [
                .verb(.paste), .verb(.pastePlain), .verb(.stack), .verb(.pin), .verb(.board),
                .verb(.context), .verb(.markdownLink), .verb(.delete)
            ])

        let image = TransformCatalog.clipGroup(
            dockIDs: ["preview-paste", "image-copy-text"], markdownLink: false)
        #expect(image.rows == [.verb(.paste), .verb(.imageText), .verb(.delete)])
        #expect(image.rows.map(\.panelIdentifier).first == "action-row-paste")
        #expect(
            TransformRow.step(.text(.uppercase)).panelIdentifier == "transform-row-text-uppercase")
        #expect(ClipVerb.allCases.compactMap(\.dockID).contains("preview-convert"))
    }

    @Test("The filter covers clip verbs, and md or mark lead with the Markdown link")
    func filteringClipVerbs() {
        let groups =
            [
                TransformCatalog.clipGroup(
                    dockIDs: ["preview-paste", "preview-pin"], markdownLink: true)
            ]
            + TransformCatalog.groups(
                kind: .url, includesRecipes: false, smartPaste: false, modelAvailable: false,
                translationCodes: [])
        let title: (TransformRow) -> String = { row in
            switch row {
            case .verb(.markdownLink): "Copy as Markdown link"
            case .verb(let verb): verb.rawValue
            case .step(let step): step.title
            default: ""
            }
        }

        for query in ["md", "mark", "MARKDOWN link"] {
            let rows = TransformCatalog.matching(groups, query: query, title: title)
                .flatMap(\.rows)
            #expect(rows.first == .verb(.markdownLink), "\(query)")
        }
        let pin = TransformCatalog.matching(groups, query: "pin", title: title)
        #expect(pin.map(\.kind) == [.clip])
        #expect(pin.first?.rows == [.verb(.pin)])
    }

    @Test("A pipeline runs its steps in order and caps at eight")
    func pipelineRuns() {
        var pipeline = TransformPipeline()
        pipeline.append(.text(.trimmed))
        pipeline.append(.text(.uppercase))
        pipeline.append(.dev(.base64Encode))

        #expect(pipeline.run(on: "  hi  ") == .text(Data("HI".utf8).base64EncodedString()))

        for _ in 0..<10 { pipeline.append(.text(.lowercase)) }
        #expect(pipeline.steps.count == TransformPipeline.maximumSteps)
        #expect(pipeline.isFull)
    }

    @Test("A step that can't transform its input names its position")
    func pipelineFailure() {
        let pipeline = TransformPipeline(steps: [.text(.trimmed), .dev(.jsonUnescape)])
        #expect(pipeline.run(on: "not a json string") == .failed(stepIndex: 1))
    }

    @Test("Steps move and remove by position")
    func pipelineEditing() {
        var pipeline = TransformPipeline(steps: [
            .text(.trimmed), .text(.uppercase), .dev(.base64Encode)
        ])
        pipeline.move(from: 2, to: 0)
        #expect(pipeline.steps == [.dev(.base64Encode), .text(.trimmed), .text(.uppercase)])
        pipeline.remove(at: 1)
        pipeline.remove(at: 9)
        #expect(pipeline.steps == [.dev(.base64Encode), .text(.uppercase)])
    }
}
