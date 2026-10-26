import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

extension BoardsHomeView {
    /// "Boards", with how much of the Free limit is used; nothing on Pro.
    var boardsHeader: some View {
        HStack {
            Text("Boards")
            Spacer()
            if model.tier != .pro, let boards = boardUsage {
                Text("\(boards.used) of \(boards.limit) · Free")
                    .textCase(nil)
                    .monospacedDigit()
                    .accessibilityIdentifier("boards-home-limit")
            }
        }
    }

    private var boardUsage: LibraryProMeter.Ceiling? {
        let userBoards = model.boards.filter { !$0.isSystem }.count
        return LibraryProMeter(boards: userBoards, pins: 0, snippets: 0)
            .ceilings.first { $0.kind == .boards }
    }

    var boardsFooter: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(
                // swiftlint:disable:next line_length
                "Tap a board to scope the history. Swipe for appearance, rename and delete; the Favorites board is built in."
            )
            if model.tier != .pro {
                Text(
                    "Free keeps up to \(PinLimits.freeMaxPinboards) boards — Gancho Pro unlocks more."
                )
            }
        }
    }

    func syncSubtitle(_ board: Pinboard) -> Text {
        let healthy: Bool
        switch model.syncStatus {
        case .paused, .failed: healthy = false
        default: healthy = true
        }
        return
            switch BoardSyncState(
                boardID: board.id, syncEnabled: model.syncController.isEnabled,
                syncHealthy: healthy,
                awaitingUpload: awaitingSync)
        {
        case .onThisDevice: Text("On this iPhone")
        case .waiting: Text("Waiting to sync")
        case .synced: Text("Synced")
        }
    }

    /// Snippets by keyword, the way they are typed; one without a keyword is
    /// listed by its title. Each opens its detail.
    var snippetsSection: some View {
        Section("Snippets") {
            ForEach(snippets) { snippet in
                NavigationLink {
                    ClipDetailView(item: snippet)
                } label: {
                    HStack(spacing: GanchoTokens.Spacing.sm) {
                        Image(systemName: "textformat")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            if let keyword = snippet.keyword, !keyword.isEmpty,
                                !ClipSafePresentation.requiresMasking(snippet)
                            {
                                Text(verbatim: keyword).font(.body.monospaced())
                                Text(verbatim: snippetTitle(snippet))
                                    .font(.footnote).foregroundStyle(.secondary)
                            } else {
                                Text(verbatim: snippetTitle(snippet))
                            }
                        }
                    }
                }
                .accessibilityIdentifier("boards-home-snippet")
            }
        }
    }

    /// A protected snippet (a synced or older row) lists as its mask only.
    private func snippetTitle(_ snippet: ClipItem) -> String {
        if ClipSafePresentation.requiresMasking(snippet) { return ClipSafePresentation.masked }
        return snippet.title.isEmpty
            ? ClipSafePresentation.displayText(for: snippet) : snippet.title
    }
}
