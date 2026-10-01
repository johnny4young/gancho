# Snippet draft recovery

The macOS Library keeps modified fields during refreshes. If the original
snippet disappears while you are editing, the draft remains in memory and
autosave stops. Choose **Save as new snippet** or **Discard draft**. Changing
selection asks you to resolve the draft first; Cancel keeps editing it.

Recovery creates a new identifier through normal classification and privacy
checks, observes the Free snippet limit, and never restores the removed item.
Protected content cannot become a permanent snippet. No draft is written to
temporary files or synchronized implicitly. Closing and reopening the cached
Library keeps its working copy; quitting the app does not persist unsaved drafts.

This describes source behavior added after v0.9.1, not the published v0.9.1 app.

Creating or demoting a snippet also checks the captured editor identity and fields after suspended writes. A newer edit keeps its editor rather than being replaced by a late navigation. If demotion lands while new text was typed, the draft enters recovery instead of disappearing.
