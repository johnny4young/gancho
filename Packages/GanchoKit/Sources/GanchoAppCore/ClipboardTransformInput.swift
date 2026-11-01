import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit

/// What ⌃⌘V and a recipe shortcut may read from the clipboard: plain text
/// only, never a protected copy or a detected secret, within the recipe limit.
public enum ClipboardTransformInput {
    public enum Outcome: Equatable, Sendable {
        case text(String)
        case refused(Refusal)
    }

    public enum Refusal: Equatable, Sendable {
        case protectedType, noText, secret, tooLarge, changed
    }

    /// `changed` is true when the clipboard's change count moved while it was
    /// read: the types checked may not describe the text that came back.
    public static func evaluate(types: Set<String>, text: String?, changed: Bool = false) -> Outcome
    {
        guard !changed else { return .refused(.changed) }
        guard types.isDisjoint(with: SensitivePasteboardTypes.captureVeto) else {
            return .refused(.protectedType)
        }
        guard let text, !text.isEmpty else { return .refused(.noText) }
        guard text.utf8.count <= TextRecipeExecutor.maximumUTF8Bytes else {
            return .refused(.tooLarge)
        }
        // A JWT or another always-masked kind stays out, as it does in the peek.
        guard SensitiveDataDetector().detect(text) == nil,
            !RuleClassifier().classify(text).prefersMaskedPreview
        else { return .refused(.secret) }
        return .text(text)
    }
}

/// The transform ⌃⌘V repeats: the last pipeline or recipe that delivered a
/// result, stored as recipe action ids, never as content.
public struct LastTransform: Equatable, Sendable {
    public static let defaultsKey = "last-transform-steps"
    public let actionIDs: [String]

    public init(actionIDs: [String]) {
        self.actionIDs = Array(actionIDs.prefix(TextRecipe.maximumSteps))
    }

    public static func load(from defaults: UserDefaults) -> LastTransform? {
        guard let ids = defaults.stringArray(forKey: defaultsKey), !ids.isEmpty else { return nil }
        return LastTransform(actionIDs: ids)
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(actionIDs, forKey: Self.defaultsKey)
    }

    /// A runnable recipe; validation still rejects unknown ids at run time.
    public var recipe: TextRecipe {
        TextRecipe(
            name: "Last transform", steps: actionIDs.map { TextActionStep(actionID: $0) })
    }
}
