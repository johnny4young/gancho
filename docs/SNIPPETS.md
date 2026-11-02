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

This behavior is published in v0.10.0.

Creating or demoting a snippet also checks the captured editor identity and
fields after suspended writes. A newer edit keeps its editor rather than being
replaced by a late navigation. If demotion lands while new text was typed, the
draft enters recovery instead of disappearing.

Saving an edit applies the same classification: protected content stays in the
editor with an inline notice and is never written or queued for sync.

Template insertion is bound to the selected persisted revision. Changing or
deleting the snippet while its fields are being filled rejects the insertion
instead of substituting a different body. Reopen it and try again. Field editors
scroll while Insert and Cancel remain visible, and the preview follows the
panel's text-size preference. Cancelling or changing the search also cancels a
pending template load.

## Suggested snippets

Clips you have used three times or more appear under **Suggested** in the macOS
Library, most used first, with how many times you used them. **Keep** saves the
clip as a snippet through the normal path, Free limit included. **Never** stops
suggesting that clip for good. **Dismiss** hides it until three more uses, when
it returns to the group and the toast in the panel offers it once more.

Snippets, secrets, masked kinds, archived and expired clips are never suggested,
and the group hides in Private Mode and while the screen is shared. Your answers
live in a local table that does not sync, and they are deleted with the clip.

## Placeholders

The **Insert placeholder** row in the editor writes these at the caret.

| Placeholder | Fills with |
| --- | --- |
| `{name}`, `{name:default}` | A field you type in the fill sheet |
| `{clipboard}` | The clipboard at the moment you insert |
| `{clipboard offset=1}` | The clip before the newest in history; 2 goes one further back |
| `{date}`, `{date +2d}`, `{date -1d}` | A date you pick in the fill sheet, starting at today plus the offset |
| `{cursor}` | Nothing: the caret lands here after pasting |

`| trim` and `| uppercase` can follow any placeholder but the cursor, as in
`{clipboard | trim}`, and they run in the order written. Anything else in braces
is pasted as written.

The fill sheet appears only when there is a field to type or a date to pick. Its
preview shows `{clipboard}` and `{cursor}` as written, because the clipboard is
read only when you insert.

A clipboard placeholder stays empty, with a toast saying so, in Private Mode and
when the clip is protected, a secret, a masked kind or not text. Pinned clips
count at their own time in history, and snippets don't count. If the caret would
have to move more than 2,000 characters, it stays at the end of the pasted text.
A name with a default, such as `{date:today}`, is still a field.
