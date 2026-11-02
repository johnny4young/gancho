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
            _ = await self?.discardMergedCopy(ids)
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
        confirmMerge(partCount: partCount)
        await refreshRecents()
        notifyStoreChanged(for: .clips)
        return true
    }

    func noteIngestedForMerge(
        _ capture: PasteboardCapture, outcome: ClipIngestionCoordinator.Outcome
    ) {
        // Tracked with merging off too, so turning it on targets the real clip before.
        let item = outcome.item
        copyMerger.didIngest(
            CopyObservation(capture), clipID: item.id, isNew: outcome.isNew,
            canPair: !ClipSafePresentation.requiresMasking(item) && item.kind.allowsTextEditing)
    }

    /// Re-joins a merged clip with another separator; false when it was refused.
    func rejoinParts(_ item: ClipItem, with separator: ClipParts.Separator) async -> Bool {
        guard let fullStore else { return false }
        let outcome = await ClipMergeWorkflow().rejoin(
            item.id, with: separator, store: fullStore, engine: syncController.engine)
        await refreshRecents()
        notifyStoreChanged(for: .clips)
        guard case .merged = outcome else {
            diagnostics.record(
                String(localized: "Editing"), String(localized: "Couldn’t change the separator."))
            return false
        }
        return true
    }

    /// Saves each part of a merged clip as its own clip, then drops the merged one.
    func splitParts(_ item: ClipItem) async {
        guard let fullStore else { return }
        let outcome = await ClipMergeWorkflow().split(
            item.id, store: fullStore,
            save: { [weak self] text in await self?.saveSplitPart(text, from: item) },
            remove: { [weak self] id in await self?.discardMergedCopy([id]) ?? false })
        await refreshRecents()
        notifyStoreChanged(for: .clips)
        switch outcome {
        case .split(let ids):
            // A part equal to a clip already in history lands in that clip.
            toasts.show(GanchoToast(message: "Split · \(Set(ids).count) clips"))
        case .failed, .refused:
            diagnostics.record(
                String(localized: "Editing"), String(localized: "Couldn’t split the clip."))
        }
    }

    /// A part goes through the capture pipeline, so it is classified, checked
    /// for secrets, deduped and synced like a copy, without counting as one
    /// or spending a free AI title.
    private func saveSplitPart(_ text: String, from item: ClipItem) async -> UUID? {
        let capture = PasteboardCapture(
            payload: .text(text), sourceAppBundleID: item.sourceAppBundleID)
        var configuration = ingestionConfiguration()
        configuration.allowsFreeTitle = false
        guard
            let outcome = try? await ingestionCoordinator.ingest(
                capture, configuration: configuration, store: store,
                syncEngine: syncController.engine)
        else { return nil }
        enrich(outcome)
        return outcome.item.id
    }

    private func confirmMerge(partCount: Int) {
        copyHUD.show(
            CopyHUD(symbol: "doc.on.doc", title: "Merged · \(partCount) parts"),
            below: toasts.visibleFrame)
        // Respects the system "Play user interface sound effects" switch too.
        guard preferences.playsMergeSound,
            UserDefaults.standard.object(forKey: "com.apple.sound.uiaudio.enabled") as? Bool
                != false
        else { return }
        let sound = NSSound(named: "Pop")
        sound?.volume = 0.4
        sound?.play()
    }

    @discardableResult
    private func discardMergedCopy(_ ids: [UUID]) async -> Bool {
        let outcome = await ClipDeletionWorkflow().delete(
            ids: ids, store: store, syncStore: fullStore, engine: syncController.engine,
            syncEnabled: syncController.isEnabled)
        reportDeletionFailure(outcome)
        if case .deleted = outcome { return true }
        return false
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
