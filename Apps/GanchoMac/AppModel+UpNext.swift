import AppKit
import GanchoAppCore
import GanchoKit

/// What the panel's Up next slot shows for the app in front.
struct UpNextSlot: Equatable {
    let item: ClipItem
    let reason: UpNextPrediction.Reason
    let targetBundleID: String
}

extension AppModel {
    /// Logs a paste-back while Up next is on and capture isn't private.
    func recordUpNextPastes(_ items: [ClipItem], targetBundleID: String?) {
        guard intelligence.upNext, !preferences.isPrivateModePaused,
            let targetBundleID = upNextTarget(targetBundleID), let fullStore
        else { return }
        let ids = items.filter { !ClipSafePresentation.requiresMasking($0) }.map(\.id)
        guard !ids.isEmpty else { return }
        upNextWrites.enqueue {
            try? await fullStore.recordPasteEvents(
                clipIDs: ids, targetBundleID: targetBundleID, at: .now)
        }
        refreshUpNext()
    }

    /// Turning Up next off erases its log; a paste queued before the switch
    /// lands first, so nothing survives the erase.
    func upNextPreferenceChanged() {
        guard !intelligence.upNext else {
            refreshUpNext()
            return
        }
        upNextRefresh?.cancel()
        upNextSlot = nil
        guard let fullStore else { return }
        upNextWrites.enqueue { try? await fullStore.clearPasteEvents() }
    }

    /// Recomputes the slot for the app in front, latest call wins.
    func refreshUpNext() {
        upNextRefresh?.cancel()
        guard intelligence.upNext, !previewsHidden, let fullStore,
            let target = upNextTarget(currentReuseTargetBundleID())
        else {
            upNextSlot = nil
            return
        }
        if upNextSlot?.targetBundleID != target { upNextSlot = nil }
        let writes = upNextWrites
        upNextRefresh = Task { [weak self] in
            await writes.drain()
            let now = Date()
            let events = (try? await fullStore.pasteEvents(targetBundleID: target, now: now)) ?? []
            let prediction = UpNextRanker.predict(events, now: now)
            var item: ClipItem?
            if let prediction { item = try? await fullStore.item(id: prediction.clipID) }
            guard !Task.isCancelled, let self, self.intelligence.upNext else { return }
            guard let prediction, let item, !ClipSafePresentation.requiresMasking(item) else {
                self.upNextSlot = nil
                return
            }
            let slot = UpNextSlot(item: item, reason: prediction.reason, targetBundleID: target)
            if self.upNextSlot != slot { self.upNextSlot = slot }
        }
    }

    /// Launch housekeeping: an erase a quit cut short, or rows past the window.
    func tidyUpNextLog() {
        guard let fullStore else { return }
        if intelligence.upNext {
            upNextWrites.enqueue { try? await fullStore.prunePasteEvents(now: .now) }
        } else {
            upNextWrites.enqueue { try? await fullStore.clearPasteEvents() }
        }
    }

    /// A paste logs against the app it was confirmed into, never a guess.
    private func upNextTarget(_ target: String?) -> String? {
        #if DEBUG
            // UI tests activate Gancho itself, so fixtures name the target app.
            if let index = CommandLine.arguments.firstIndex(of: "-ui-test-up-next-target"),
                CommandLine.arguments.indices.contains(index + 1)
            {
                return CommandLine.arguments[index + 1]
            }
        #endif
        return target
    }

    /// `-seed-up-next`: an older code clip pasted three times today into the
    /// fixture target, under two newer clips, with Up next on.
    func seedUpNextIfRequested() -> Task<Void, Never>? {
        #if DEBUG
            guard CommandLine.arguments.contains("-seed-up-next"),
                CommandLine.arguments.contains("-use-temp-durable-store"), let fullStore,
                let target = upNextTarget(nil)
            else { return nil }
            intelligence.upNext = true
            return Task {
                let now = Date()
                let predicted = ClipItem(
                    createdAt: now.addingTimeInterval(-3_600), kind: .code,
                    title: "Greeting", preview: #"let greeting = "Hello""#,
                    contentHash: "up-next-code")
                _ = try? await fullStore.insert(
                    predicted, content: .text(#"let greeting = "Hello""#))
                for (offset, text) in [(-120.0, "Seed sign-off"), (-60.0, "seed newest")] {
                    _ = try? await fullStore.insert(
                        ClipItem(
                            createdAt: now.addingTimeInterval(offset), title: text,
                            preview: text, contentHash: "up-next-\(text)"),
                        content: .text(text))
                }
                for minutes in [30.0, 20.0, 10.0] {
                    try? await fullStore.recordPasteEvents(
                        clipIDs: [predicted.id], targetBundleID: target,
                        at: now.addingTimeInterval(-minutes * 60))
                }
                await refreshRecents()
                refreshUpNext()
            }
        #else
            return nil
        #endif
    }
}
