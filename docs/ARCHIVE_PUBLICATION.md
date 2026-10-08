# Portable archive publication

`GanchoArchive.export` creates a version-1 `.ganchoarchive` directory containing
`clips.json`, declared binary blobs, and a checksummed manifest. The row encoding
and restore format are unchanged.

## Destination replacement policy

The API now defaults to `replacement: .failIfExists`. Existing source calls still
compile, and exports to fresh destinations behave as before. A call targeting an
existing archive now fails without changing it unless the caller explicitly
selects `.replaceExisting`. This is an intentional safety change from the former
implicit, per-file overwrite behavior.

Select `.replaceExisting` only after obtaining a replacement decision for a
user-owned destination, or for a temporary destination owned by the application.
It replaces the complete directory, including files not declared in its manifest;
it is not a merge into an arbitrary directory. Replacement is therefore limited to
a directory that is already a Gancho archive (its `manifest.json` decodes as a
supported Gancho manifest) or is empty apart from Finder's `.DS_Store`. Any other
existing folder — for example one named in a save panel by mistake, including one
that merely holds an unrelated `manifest.json` — is refused untouched with a
"file exists" error. The destination is checked before any export work starts,
and again at promotion time.

Current production call sites:

- macOS: `Apps/GanchoMac/SettingsView.swift`, `backupHistory()`, passes
  `.replaceExisting` after `NSSavePanel` accepts the destination and its normal
  replacement decision
- iOS: `Apps/GanchoiOS/IOSAppModel.swift`, `makeBackupArchive()`, passes
  `.replaceExisting` for its fixed application-owned temporary archive, before
  the system file exporter presents the user's final Files destination. Anything
  left at that app-owned temporary path (an earlier export, or an interrupted
  in-place export from an older build) is removed first, so a failed export never
  leaves a stale plaintext archive there
- CLI: `Packages/GanchoKit/Sources/gancho/GanchoCLI.swift`, `runExport()`, produces
  plain JSON or CSV through `exportJSON`/`exportCSV`. It does not call
  `GanchoArchive.export` or produce a portable archive, so this directory
  replacement policy does not change its output behavior

## Ownership and failure behavior

The exporter builds the complete result in a private, uniquely named sibling
stage, writing each file in place because the whole stage is discarded on failure. It verifies the stored manifest and streams file checksum validation with
bounded memory. Cancellation is checked between export phases, per blob, while validating, and
before publication; the row stream inside GRDB's read is cancelled by GRDB itself. None of those operations modifies the selected destination.

Publication uses Darwin's exclusive rename for a fresh destination and atomic
`RENAME_SWAP` for explicitly replacing an existing directory on a filesystem that
supports it. Volumes without `renameatx_np` flag support (exFAT, FAT and some SMB
shares report `ENOTSUP` or `EINVAL`) can still receive a NEW archive: after
checking that nothing exists at the destination, the stage is moved with a plain
rename. Replacing an existing archive on such a volume fails while retaining the
previous archive; there is no remove-then-move fallback. A successful exchange leaves the
former archive at the owned stage path until best-effort cleanup completes. An
interruption can therefore leave a recoverable hidden stage.

Failure cleanup removes only the stage owned by that export. Neither application
call site deletes the selected destination on failure. Cleanup after a successful
exchange is best-effort, so an old-stage cleanup failure does not falsely report
that an already published backup failed.

## Qualification

The regression suite checks byte-for-byte preservation of an existing archive and
an unrelated sentinel, restoreability, cancellation, missing source blobs,
injected row/blob/manifest/promotion failures, explicit replacement refusal
(including a foreign folder holding an unrelated `manifest.json`),
successful complete replacement, and the real Darwin rename error path using
isolated fixture directories. No live backup or Keychain is used.

Native macOS/iOS compilation, test execution, Save Panel behavior, and target
filesystem support must still be qualified by CI or disposable native fixtures.
Source-directed POSIX models are supplementary evidence, not those native gates.
