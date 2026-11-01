import AppKit
import ClipboardCore
import Foundation
import GanchoAppCore
import GanchoKit

/// Double-copy merging: the same text copied twice in quick succession
/// appends to the clip before it.
extension AppModel {
    /// Merges when this capture completes a double copy; false means ingest it.
    func mergeDoubleCopyIfNeeded(_ capture: PasteboardCapture) async -> Bool {
        guard preferences.mergeDoubleCopies, let fullStore,
            case .merge(let text, let target, let discard) = copyMerger.decide(
                CopyObservation(capture))
        else { return false }
        let deletion: @Sendable ([UUID]) async -> Void = { [weak self] ids in
            await self?.discardMergedCopy(ids)
        }
        let outcome = await ClipMergeWorkflow().merge(
            text, into: target, discarding: discard, store: fullStore, deletion: deletion,
            engine: syncController.engine)
        guard case .merged(_, let merged, let partCount) = outcome else { return false }
        copyMerger.didMerge(into: target)
        // ⌘V pastes what the history now holds, unless a newer copy landed or
        // the screen became private meanwhile.
        if NSPasteboard.general.changeCount == capture.change?.count,
            !preferences.isPrivateModePaused, sharingAppName == nil
        {
            writeManualText(merged)
        }
        toasts.show(GanchoToast(message: "Merged · \(partCount) parts"))
        await refreshRecents()
        notifyStoreChanged(for: .clips)
        return true
    }

    func noteIngestedForMerge(
        _ capture: PasteboardCapture, outcome: ClipIngestionCoordinator.Outcome
    ) {
        guard preferences.mergeDoubleCopies else { return }
        let item = outcome.item
        copyMerger.didIngest(
            CopyObservation(capture), clipID: item.id, isNew: outcome.isNew,
            canPair: !ClipSafePresentation.requiresMasking(item) && item.kind.allowsTextEditing)
    }

    private func discardMergedCopy(_ ids: [UUID]) async {
        _ = await ClipDeletionWorkflow().delete(
            ids: ids, store: store, syncStore: fullStore, engine: syncController.engine,
            syncEnabled: syncController.isEnabled)
    }

    /// `-seed-double-copy`: three captures through the real ingest path, the
    /// last two the same text 0.2 s apart, with merging on.
    func seedDoubleCopyIfRequested() -> Task<Void, Never>? {
        #if DEBUG
            guard CommandLine.arguments.contains("-seed-double-copy"),
                CommandLine.arguments.contains("-use-temp-durable-store"),
                CommandLine.arguments.contains("-ui-test-paste-sink")
            else { return nil }
            preferences.mergeDoubleCopies = true
            let now = Date()
            let copies: [(String, Int, TimeInterval)] = [
                ("Ana Restrepo", 1, -5), ("Cra. 43A #1-50", 2, -1), ("Cra. 43A #1-50", 3, -0.8)
            ]
            let tasks = copies.compactMap { text, count, offset in
                ingest(
                    PasteboardCapture(
                        payload: .text(text), sourceAppBundleID: "com.apple.Safari",
                        change: .init(count: count, observedAt: now.addingTimeInterval(offset))))
            }
            return Task { for task in tasks { await task.value } }
        #else
            return nil
        #endif
    }
}
