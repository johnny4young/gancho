#if os(macOS)
    import ClipboardCore
    import Foundation
    import GanchoKit

    /// What one paste into the frontmost app came to.
    public enum PasteBackDelivery: Sendable, Equatable {
        /// There was no content to paste — the clip could not be loaded — so the
        /// panel stayed where it was and no reuse was recorded.
        case unavailable
        /// The content reached the pasteboard. `outcome` says whether ⌘V was
        /// posted as well, or Accessibility limited it to a copy.
        case delivered(PasteBackOutcome)
    }

    /// The one sequence every macOS paste runs — a stored clip, a transformed
    /// one, a filled snippet, or a Smart Paste result — so those entry points
    /// stop drifting apart.
    ///
    /// The order is the contract. The panel hides first and focus gets a beat to
    /// return to the app the user was working in, because ⌘V posted any sooner
    /// lands in whatever still holds focus. Only then is the paste posted and the
    /// timing interval closed. A copy-only outcome is noticed next, before any
    /// bookkeeping, so the user learns the paste did not land without waiting on
    /// a store write. Last, the reuse ledger credits the intended app only when
    /// the paste really was: a copy-only outcome put nothing into that app, so
    /// crediting it would misreport where the clip was used.
    ///
    /// Presentation stays with the caller: a copy-only outcome is reported through
    /// ``Effects/noticeCopyOnly``, and whatever else an entry point does — a
    /// plain-text confirmation, activation counters, a reuse suggestion, a
    /// snippet's usage count — happens after `deliver` returns.
    @MainActor
    public struct PasteBackWorkflow {
        /// The platform side effects, injected so the sequence is testable without
        /// a panel, a pasteboard, or Accessibility.
        public struct Effects {
            /// Hides the panel so focus can go back to the target app.
            public var hidePanel: @MainActor () -> Void
            /// Waits for that focus hand-back before anything is posted.
            public var waitForFocusToReturn: @MainActor () async -> Void
            /// Writes the content and posts ⌘V when Accessibility allows it.
            public var paste: @MainActor (ClipContent, _ asPlainText: Bool) -> PasteBackOutcome
            /// Tells the user the clip was copied rather than pasted, and why.
            public var noticeCopyOnly: @MainActor () -> Void

            public init(
                hidePanel: @escaping @MainActor () -> Void,
                waitForFocusToReturn: @escaping @MainActor () async -> Void,
                paste: @escaping @MainActor (ClipContent, _ asPlainText: Bool) -> PasteBackOutcome,
                noticeCopyOnly: @escaping @MainActor () -> Void
            ) {
                self.hidePanel = hidePanel
                self.waitForFocusToReturn = waitForFocusToReturn
                self.paste = paste
                self.noticeCopyOnly = noticeCopyOnly
            }
        }

        private let effects: Effects

        public init(effects: Effects) {
            self.effects = effects
        }

        /// Pastes `content` into the frontmost app.
        ///
        /// - Parameters:
        ///   - content: What to paste, or nil when the clip could not be loaded —
        ///     in which case nothing else happens.
        ///   - asPlainText: Strips rich representations before writing.
        ///   - intendedTarget: The frontmost app's bundle identifier, which the
        ///     caller reads BEFORE the panel hides.
        ///   - endInterval: Runs exactly once, as soon as the paste is posted or
        ///     abandoned, so a timing interval never includes the bookkeeping.
        ///   - recordReuse: Receives `intendedTarget` when the paste was posted,
        ///     and nil when it was only copied.
        @discardableResult
        public func deliver(
            _ content: ClipContent?,
            asPlainText: Bool,
            intendedTarget: String?,
            endInterval: @MainActor () -> Void = {},
            recordReuse: @MainActor (_ confirmedTarget: String?) async -> Void
        ) async -> PasteBackDelivery {
            guard let content else {
                endInterval()
                return .unavailable
            }
            effects.hidePanel()
            await effects.waitForFocusToReturn()
            let outcome = effects.paste(content, asPlainText)
            endInterval()
            if outcome == .copiedOnly {
                effects.noticeCopyOnly()
            }
            await recordReuse(outcome == .pasted ? intendedTarget : nil)
            return .delivered(outcome)
        }
    }
#endif
