import ClipboardCore
import GanchoAppCore
import GanchoKit
import SwiftUI

extension LibraryView {
    func loadSnippet(id: UUID, generation: UUID) async {
        guard let snippet = snippets.first(where: { $0.id == id }) else {
            reconcileMissingSnippet(id: id)
            return
        }
        if draft.snippetID == id, draft.requiresRecovery { return }
        do {
            guard let before = try await model.store.item(id: id),
                !ClipSafePresentation.requiresMasking(before),
                before.expiresAt.map({ $0 > .now }) ?? true
            else {
                guard generation == loadGeneration else { return }
                reconcileMissingSnippet(id: id)
                return
            }
            guard generation == loadGeneration else { return }
            let content = try await model.store.content(for: id)
            guard generation == loadGeneration else { return }
            let current = try await model.store.item(id: id)
            guard generation == loadGeneration else { return }
            guard case .text(let body) = content, let current,
                !ClipSafePresentation.requiresMasking(current),
                current.expiresAt.map({ $0 > .now }) ?? true
            else {
                reconcileMissingSnippet(id: id)
                return
            }
            guard before.updatedAt == current.updatedAt, before.contentHash == current.contentHash
            else { return }
            draft.reload(
                snippetID: id,
                stored: .init(title: current.title, keyword: current.keyword ?? "", body: body))
            editingSnippet = snippet
        } catch {
            model.diagnostics.record(
                "Snippets", String(localized: "Couldn’t load snippets; your draft is still here."))
        }
    }

    private func reconcileMissingSnippet(id: UUID) {
        draft.markMissing(snippetID: id)
        if !draft.requiresRecovery {
            editingSnippet = nil
            draft = SnippetDraft()
        }
    }

    func requestSelection(_ next: LibrarySelection?) {
        guard next != selection, !isSavingDraft else { return }
        if draft.requiresRecovery {
            pendingDraftSelection = next ?? .allClips
            showsDraftResolution = true
            return
        }
        let previous = selection
        let leaving = draft
        selectionTask?.cancel()
        isSavingDraft = leaving.isDirty
        selectionTask = Task {
            defer { isSavingDraft = false }
            if let id = leaving.snippetID, leaving.isDirty {
                guard await writeDraft(id: id, fields: leaving.edited) else {
                    if draft.requiresRecovery {
                        pendingDraftSelection = next ?? .allClips
                        showsDraftResolution = true
                    }
                    return
                }
            }
            guard !Task.isCancelled, selection == previous, draft.edited == leaving.edited else {
                return
            }
            selection = next
        }
    }

    func save() {
        guard let id = draft.snippetID, draft.isDirty, !draft.isMissing, !isSavingDraft else {
            return
        }
        let fields = draft.edited
        isSavingDraft = true
        selectionTask = Task {
            defer { isSavingDraft = false }
            _ = await writeDraft(id: id, fields: fields)
        }
    }

    private func writeDraft(id: UUID, fields: SnippetDraft.Fields) async -> Bool {
        guard let store = model.fullStore, !Task.isCancelled,
            !(draft.snippetID == id && draft.isMissing)
        else { return false }
        #if DEBUG
            if CommandLine.arguments.contains("-ui-test-snippet-save-failure"),
                CommandLine.arguments.contains("-use-temp-durable-store"),
                AppModel.uiTestDefaultsSuiteName() != nil
            {
                model.diagnostics.record("Snippets", "Couldn’t save that snippet.")
                return false
            }
        #endif
        do {
            let saved = try await store.updateSnippetDraft(
                id: id, title: fields.title, text: fields.body, keyword: fields.keyword)
            guard saved else {
                draft.markMissing(snippetID: id)
                return false
            }
            draft.markSaved(snippetID: id, fields)
            snippets = try await store.snippets()
            model.refreshSpotlight()
            return true
        } catch {
            model.diagnostics.record("Snippets", "Couldn’t save that snippet.")
            return false
        }
    }

    func recoverDraft() {
        guard let store = model.fullStore, draft.requiresRecovery, !isSavingDraft else { return }
        let fields = draft.edited
        let originalID = draft.snippetID
        let destination = pendingDraftSelection
        isSavingDraft = true
        selectionTask = Task {
            defer { isSavingDraft = false }
            do {
                let prepared = try SnippetDraftRecovery.prepare(
                    fields, sensitiveLifetime: model.retentionPolicy.sensitiveLifetime,
                    detectSecrets: model.intelligence.detectSecrets,
                    fallbackTitle: String(localized: "Recovered snippet"))
                let recovered = try await store.saveRecoveredSnippet(
                    item: prepared.item, text: prepared.text, keyword: fields.keyword,
                    isPro: model.tier == .pro)
                guard draft.snippetID == originalID else { return }
                draft = SnippetDraft()
                pendingDraftSelection = nil
                snippets.insert(recovered, at: 0)
                editingSnippet = recovered
                draft = SnippetDraft(
                    snippetID: recovered.id,
                    stored: .init(
                        title: recovered.title, keyword: recovered.keyword ?? "",
                        body: prepared.text))
                selection = destination ?? .snippet(recovered.id)
                model.recordActivationMilestone(.firstSnippetCreated)
                model.refreshSpotlight()
            } catch SnippetDraftSaveError.freeLimitReached {
                model.paywallWindow.show(trigger: .freeLimitReached, model: model)
            } catch SnippetDraftSaveError.protectedContent {
                model.diagnostics.record(
                    "Snippets", "Protected content cannot be saved as a snippet.")
            } catch {
                model.diagnostics.record("Snippets", "Couldn’t save that snippet.")
            }
        }
    }

    func discardDraft() {
        guard !isSavingDraft else { return }
        let destination = pendingDraftSelection ?? .allClips
        pendingDraftSelection = nil
        editingSnippet = nil
        draft = SnippetDraft()
        selection = destination
    }

    func demote() {
        guard let editingSnippet, !draft.isMissing, !isSavingDraft else { return }
        let fields = draft.edited
        let dirty = draft.isDirty
        isSavingDraft = true
        selectionTask = Task {
            defer { isSavingDraft = false }
            if dirty, !(await writeDraft(id: editingSnippet.id, fields: fields)) { return }
            do {
                guard draft.snippetID == editingSnippet.id, draft.edited == fields else { return }
                try await model.fullStore?.demoteFromSnippet(id: editingSnippet.id)
                guard draft.snippetID == editingSnippet.id, draft.edited == fields else {
                    draft.markMissing(snippetID: editingSnippet.id)
                    await refreshAll()
                    return
                }
                draft = SnippetDraft()
                selection = .allClips
                await refreshAll()
                model.refreshSpotlight()
            } catch { model.diagnostics.record("Snippets", "Couldn’t save that snippet.") }
        }
    }

    func createSnippet() {
        guard let store = model.fullStore, !isSavingDraft else { return }
        guard !draft.requiresRecovery else {
            showsDraftResolution = true
            return
        }
        let leaving = draft
        isSavingDraft = true
        selectionTask = Task {
            defer { isSavingDraft = false }
            if let id = leaving.snippetID, leaving.isDirty,
                !(await writeDraft(id: id, fields: leaving.edited))
            {
                return
            }
            guard !Task.isCancelled, draft.snippetID == leaving.snippetID,
                draft.edited == leaving.edited
            else { return }
            do {
                let text = String(localized: "New snippet")
                let prepared = try SnippetDraftRecovery.prepare(
                    .init(title: text, body: text),
                    sensitiveLifetime: model.retentionPolicy.sensitiveLifetime,
                    detectSecrets: model.intelligence.detectSecrets, fallbackTitle: text)
                let item = try await store.saveRecoveredSnippet(
                    item: prepared.item, text: prepared.text, keyword: nil,
                    isPro: model.tier == .pro)
                snippets.insert(item, at: 0)
                guard draft.snippetID == leaving.snippetID, draft.edited == leaving.edited else {
                    return
                }
                selection = .snippet(item.id)
                model.recordActivationMilestone(.firstSnippetCreated)
                model.refreshSpotlight()
            } catch SnippetDraftSaveError.freeLimitReached {
                model.paywallWindow.show(trigger: .freeLimitReached, model: model)
            } catch { model.diagnostics.record("Snippets", "Couldn’t save that snippet.") }
        }
    }

    #if DEBUG
        func simulateSnippetDeletion(id: UUID) {
            guard CommandLine.arguments.contains("-use-temp-durable-store"),
                AppModel.uiTestDefaultsSuiteName() != nil
            else { return }
            Task {
                try? await model.fullStore?.delete(id: id)
                await refreshAll()
            }
        }
    #endif
}
