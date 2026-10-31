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
