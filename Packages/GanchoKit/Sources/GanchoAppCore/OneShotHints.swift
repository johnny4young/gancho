import Foundation

/// A contextual "did you know" hint shown at most ONCE, ever — the moment the
/// user first hits the situation it teaches. Content-free by construction: the
/// model records only which hints have fired (a small set of stable keys), so
/// it never touches clipboard data and its persistence is a handful of booleans.
public enum Hint: String, Sendable, CaseIterable {
    /// After a few arrow-key selections: teach ⌘1..9 direct paste.
    case quickPasteNumbers = "hint.quick-paste-numbers"
    /// On the third board: teach ⌘B to file the selected clip.
    case fileWithCommandB = "hint.file-with-command-b"
    /// On a long text clip: teach ⌘Y for the full read-only preview.
    case fullPreviewCommandY = "hint.full-preview-command-y"

    /// How many times its trigger must occur before the hint fires. A hint
    /// that teaches a shortcut for a REPEATED action waits until the user has
    /// clearly settled into the slow path (so it never interrupts a first-time
    /// explorer), while a one-off affordance can fire on first sight.
    public var threshold: Int {
        switch self {
        case .quickPasteNumbers: return 3
        case .fileWithCommandB: return 3
        case .fullPreviewCommandY: return 1
        }
    }
}

/// The minimal persistence the hint model needs — a bool store keyed by
/// string. `UserDefaults` conforms in the shells; tests pass an in-memory fake,
/// so the "fires exactly once" rule is verified without touching real defaults.
public protocol HintStore: AnyObject, Sendable {
    func bool(forKey key: String) -> Bool
    func set(_ value: Bool, forKey key: String)
    func integer(forKey key: String) -> Int
    func set(_ value: Int, forKey key: String)
}

/// Decides whether a contextual hint should surface now. Each trigger bumps a
/// content-free counter; when it crosses the hint's threshold AND the hint has
/// never fired, `noteTrigger` returns the hint once and marks it shown. Every
/// later call returns nil. Pure policy over the injected store — no UI, no
/// clipboard access.
public struct OneShotHints: Sendable {
    private let store: any HintStore

    public init(store: any HintStore) {
        self.store = store
    }

    private func firedKey(_ hint: Hint) -> String { "\(hint.rawValue).fired" }
    private func countKey(_ hint: Hint) -> String { "\(hint.rawValue).count" }

    /// True once the hint has fired and been dismissed — it never returns.
    public func hasFired(_ hint: Hint) -> Bool {
        store.bool(forKey: firedKey(hint))
    }

    /// Records one occurrence of `hint`'s trigger. Returns the hint the FIRST
    /// time the count reaches its threshold; nil otherwise (below threshold,
    /// or already fired). Marks it fired when it returns it, so it is a
    /// strict once-ever surface.
    @discardableResult
    public func noteTrigger(_ hint: Hint) -> Hint? {
        guard !hasFired(hint) else { return nil }
        let next = store.integer(forKey: countKey(hint)) + 1
        store.set(next, forKey: countKey(hint))
        guard next >= hint.threshold else { return nil }
        store.set(true, forKey: firedKey(hint))
        return hint
    }

    /// Suppress a hint without waiting for its trigger — e.g. the user already
    /// used the shortcut it would teach, so teaching it is noise.
    public func suppress(_ hint: Hint) {
        store.set(true, forKey: firedKey(hint))
    }
}
