import Foundation
import GanchoAI
import GanchoKit

/// One deterministic step of the peek's Transform pipeline: a text transform
/// or one of the kind's developer actions. Pure, offline, no model.
public enum TransformStep: Hashable, Sendable {
    case text(PasteTransform)
    case dev(DevActions.ActionID)

    /// English title; the UI localizes it through the String Catalog.
    public var title: String {
        switch self {
        case .text(let transform): transform.title
        case .dev(let id): DevActions.action(id).title
        }
    }

    public var id: String {
        switch self {
        case .text(let transform): "text-\(transform.rawValue)"
        case .dev(let id): "dev-\(id.rawValue)"
        }
    }

    public func apply(to text: String) throws -> String {
        switch self {
        case .text(let transform): transform.apply(to: text)
        case .dev(let id): try DevActions.run(id, on: text)
        }
    }
}

/// The steps a pipeline runs in order. Capped like a text recipe.
public struct TransformPipeline: Equatable, Sendable {
    public static let maximumSteps = 8

    public private(set) var steps: [TransformStep] = []

    public init(steps: [TransformStep] = []) {
        self.steps = Array(steps.prefix(Self.maximumSteps))
    }

    public var isEmpty: Bool { steps.isEmpty }
    public var isFull: Bool { steps.count >= Self.maximumSteps }

    public mutating func append(_ step: TransformStep) {
        guard !isFull else { return }
        steps.append(step)
    }

    public mutating func remove(at index: Int) {
        guard steps.indices.contains(index) else { return }
        steps.remove(at: index)
    }

    /// Moves one step to a new position (an index into the list after removal).
    public mutating func move(from source: Int, to destination: Int) {
        guard steps.indices.contains(source), source != destination else { return }
        let step = steps.remove(at: source)
        steps.insert(step, at: min(max(destination, 0), steps.count))
    }

    public enum Outcome: Equatable, Sendable {
        case text(String)
        /// The step at this index can't transform what reached it.
        case failed(stepIndex: Int)
    }

    public func run(on text: String) -> Outcome {
        var current = text
        for (index, step) in steps.enumerated() {
            guard let next = try? step.apply(to: current) else { return .failed(stepIndex: index) }
            current = next
        }
        return .text(current)
    }
}

/// The single Transform list: what each row of the ⌘T popover does.
public enum TransformRow: Hashable, Sendable, Identifiable {
    /// Opens the text recipes.
    case recipes
    /// Opens the pipeline with this step and its before / after.
    case step(TransformStep)
    /// An on-device rewrite into the result box.
    case smartPaste(SmartPasteAction)
    /// A translation into an installed language, by code.
    case translate(String)

    public var id: String {
        switch self {
        case .recipes: "recipes"
        case .step(let step): step.id
        case .smartPaste(let action): "smart-\(action.rawValue)"
        case .translate(let code): "translate-\(code)"
        }
    }
}

public struct TransformGroup: Equatable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        /// The clip's own developer actions, titled by its kind.
        case clipKind(ClipContentKind)
        case text, recipes, smartPaste
    }

    public let kind: Kind
    public let rows: [TransformRow]
    public var id: Kind { kind }
}

public enum TransformCatalog {
    /// What the popover offers for a clip, in order: the kind's own actions
    /// first, then text transforms, recipes and on-device Smart paste.
    /// `plainText` stays out: Paste plain already covers it.
    public static func groups(
        kind: ClipContentKind, includesRecipes: Bool, smartPaste: Bool, modelAvailable: Bool,
        translationCodes: [String]
    ) -> [TransformGroup] {
        var groups: [TransformGroup] = []
        let dev = DevActions.actions(for: kind).map { TransformRow.step(.dev($0.id)) }
        if !dev.isEmpty { groups.append(TransformGroup(kind: .clipKind(kind), rows: dev)) }
        groups.append(
            TransformGroup(
                kind: .text,
                rows: PasteTransform.allCases.filter { $0 != .plainText }.map { .step(.text($0)) }))
        if includesRecipes { groups.append(TransformGroup(kind: .recipes, rows: [.recipes])) }
        if smartPaste {
            // Redact PII is deterministic, so it stays without the model.
            let actions = SmartPasteAction.allCases.filter { $0 == .redactPII || modelAvailable }
            let rows =
                actions.map(TransformRow.smartPaste) + translationCodes.map(TransformRow.translate)
            if !rows.isEmpty { groups.append(TransformGroup(kind: .smartPaste, rows: rows)) }
        }
        return groups
    }

    /// Keeps the rows whose title contains every word of the query, ignoring
    /// case and diacritics; empty groups drop out.
    public static func matching(
        _ groups: [TransformGroup], query: String, title: (TransformRow) -> String
    ) -> [TransformGroup] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return groups }
        return groups.compactMap { group in
            let rows = group.rows.filter { row in
                let haystack = title(row)
                return words.allSatisfy {
                    haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive])
                        != nil
                }
            }
            return rows.isEmpty ? nil : TransformGroup(kind: group.kind, rows: rows)
        }
    }

    /// The deterministic steps "+ step" can add for a clip kind.
    public static func steps(for kind: ClipContentKind) -> [TransformStep] {
        DevActions.actions(for: kind).map { .dev($0.id) }
            + PasteTransform.allCases.filter { $0 != .plainText }.map { .text($0) }
    }
}
