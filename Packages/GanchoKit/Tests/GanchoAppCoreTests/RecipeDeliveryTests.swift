import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Recipe steps, saved pipelines and clipboard input")
struct RecipeDeliveryTests {
    @Test("Recipe dev steps mirror DevActions, ids and titles")
    func devDescriptorsMirrorDevActions() {
        let dev = TextActionCatalog.descriptors.filter {
            $0.id.hasPrefix(TextActionCatalog.devPrefix)
        }
        #expect(dev.map(\.id) == DevActions.ActionID.allCases.map { "dev.\($0.rawValue)" })
        #expect(
            dev.map(\.title) == DevActions.ActionID.allCases.map { DevActions.action($0).title })
    }

    @Test("A saved pipeline is a valid recipe that runs the same steps")
    func pipelineSavesAsRecipe() async throws {
        let pipeline = TransformPipeline(steps: [.text(.trimmed), .dev(.base64Encode)])
        let recipe = pipeline.recipe(named: "Encode")

        try recipe.validate()
        #expect(recipe.steps.map(\.actionID) == ["transform.trimmed", "dev.base64Encode"])
        let output = try await TextRecipeExecutor().run(recipe, on: "  hi  ")
        #expect(.text(output) == pipeline.run(on: "  hi  "))
        #expect(
            recipe.steps.compactMap { TransformStep(recipeActionID: $0.actionID) } == pipeline.steps
        )
        #expect(TransformStep(recipeActionID: "redact-pii") == nil)
    }

    @Test("Protected types, empty text, secrets and oversize text are refused")
    func clipboardGate() {
        #expect(
            ClipboardTransformInput.evaluate(
                types: [SensitivePasteboardTypes.concealed], text: "x") == .refused(.protectedType))
        #expect(ClipboardTransformInput.evaluate(types: [], text: nil) == .refused(.noText))
        #expect(
            ClipboardTransformInput.evaluate(types: [], text: "AKIAIOSFODNN7EXAMPLE")
                == .refused(.secret))
        let huge = String(repeating: "a", count: TextRecipeExecutor.maximumUTF8Bytes + 1)
        #expect(ClipboardTransformInput.evaluate(types: [], text: huge) == .refused(.tooLarge))
        #expect(
            ClipboardTransformInput.evaluate(types: [], text: "hola", changed: false)
                == .text("hola"))
        #expect(
            ClipboardTransformInput.evaluate(types: [], text: "hola", changed: true)
                == .refused(.changed))
        #expect(
            ClipboardTransformInput.evaluate(types: ["public.utf8-plain-text"], text: "hola")
                == .text("hola"))
    }

    @Test("A JWT the secret detector misses still stays out, as in the peek")
    func maskedKindsStayOut() throws {
        // Built at run time so no token literal sits in the source. Longer than the
        // password heuristic's 64-character band, like a real token.
        let segment: (String) -> String = {
            Data($0.utf8).base64EncodedString()
                .replacingOccurrences(of: "=", with: "")
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }
        let jwt = [
            segment(#"{"alg":"HS256","typ":"JWT"}"#), segment(#"{"sub":"1234567890"}"#),
            segment("synthetic")
        ].joined(separator: ".")
        try #require(SensitiveDataDetector().detect(jwt) == nil)
        try #require(RuleClassifier().classify(jwt) == .jwt)
        #expect(ClipboardTransformInput.evaluate(types: [], text: jwt) == .refused(.secret))
    }

    @Test("The last transform keeps ids only, round-trips and caps at eight")
    func lastTransform() throws {
        let defaults = try #require(UserDefaults(suiteName: "last-transform-\(UUID().uuidString)"))
        #expect(LastTransform.load(from: defaults) == nil)
        LastTransform(actionIDs: Array(repeating: "transform.trimmed", count: 12)).save(
            to: defaults)
        let loaded = try #require(LastTransform.load(from: defaults))
        #expect(loaded.actionIDs.count == TextRecipe.maximumSteps)
        try loaded.recipe.validate()
    }
}
