import Foundation
import GanchoKit

/// What the status-item menu lists, top to bottom. Pure, so the order, the
/// ⌘1–5 numbering, the masking and the stack row are unit-tested; the app turns
/// it into an `NSMenu`.
public struct MenuBarMenuPlan: Equatable, Sendable {
    public static let recentLimit = 5

    public enum Command: Equatable, Sendable, CaseIterable {
        case openPanel, library, copyScreenText
        case toggleCapture, togglePrivateMode, ignoreNextCopy
        case settings, privacyCenter, welcome, wrapped
        case fixClipboardAccess, quit
    }

    public struct Recent: Equatable, Sendable {
        public let clip: ClipItem
        /// 1–5, the row's ⌘ key; ⌥⌘ pastes it plain.
        public let number: Int
        /// Kind only: the clip is sensitive, or previews are hidden.
        public let masked: Bool
    }

    public struct Stack: Equatable, Sendable {
        public let waiting: Int
        public let next: ClipItem
        public let nextMasked: Bool
    }

    public enum Entry: Equatable, Sendable {
        case header
        case recentsLabel
        case recent(Recent)
        case noRecents
        case stack(Stack)
        case command(Command)
        case separator
    }

    public let entries: [Entry]

    /// - Parameters:
    ///   - previewsHidden: Private Mode, or a screen share the user hasn't
    ///     revealed; every row then shows its kind only.
    ///   - accessDenied: offers Fix right under the header.
    public init(
        recents: [ClipItem], stack: [ClipItem], previewsHidden: Bool, accessDenied: Bool
    ) {
        var entries: [Entry] = [.header]
        if accessDenied { entries.append(.command(.fixClipboardAccess)) }
        entries.append(.recentsLabel)
        let shown = recents.prefix(Self.recentLimit)
        if shown.isEmpty {
            entries.append(.noRecents)
        } else {
            for (offset, clip) in shown.enumerated() {
                entries.append(
                    .recent(
                        Recent(
                            clip: clip, number: offset + 1,
                            masked: previewsHidden || ClipSafePresentation.requiresMasking(clip))))
            }
        }
        entries.append(.separator)
        entries.append(contentsOf: [.command(.openPanel), .command(.library)])
        if let next = stack.first {
            entries.append(
                .stack(
                    Stack(
                        waiting: stack.count, next: next,
                        nextMasked: previewsHidden || ClipSafePresentation.requiresMasking(next))))
        }
        entries.append(.command(.copyScreenText))
        entries.append(.separator)
        entries.append(
            contentsOf: [Command.toggleCapture, .togglePrivateMode, .ignoreNextCopy].map(
                Entry.command))
        entries.append(.separator)
        entries.append(
            contentsOf: [Command.settings, .privacyCenter, .welcome, .wrapped].map(Entry.command))
        entries.append(.separator)
        entries.append(.command(.quit))
        self.entries = entries
    }
}
