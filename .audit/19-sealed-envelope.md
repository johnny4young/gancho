# 19 — SealedEnvelope: one primitive for content crossing the store boundary

**Date:** 2026-07-02 · **Implements:** A-8 + the "Cross-cutting theme" recommendation from
`.audit/14-security-performance-deep-dive.md` (sequenced after A-1's CKAsset staging lifecycle,
which already landed). **Constraint honored:** no Swift toolchain here — edits mirror in-file
patterns exactly; CI must compile-verify.

## 1. The primitive — `GanchoKit/SealedEnvelope.swift` [NEW]

`public enum SealedEnvelope` extracts `BlobStore`'s AES-GCM framing into the single shared
seal/open path the deep-dive called for:

- `seal(_:key:)` → `magic ‖ AES.GCM(nonce ‖ ciphertext ‖ tag)` (the `combined` representation)
- `open(_:key:)` → verifies+decrypts; bytes **without** the magic pass through as plaintext
  (deliberately mirrors `BlobStore.decodeFromDisk`, and is what makes legacy files drainable)
- `isSealed(_:)` → header check
- `magic` = the exact 11 bytes `BlobStore` has always written (`GanchoBlob` + `0x01`)

**BlobStore was refactored to delegate, not duplicated.** The refactor is byte-identical by
inspection: `encodeForDisk` was `magic + seal(...).combined` and is now `SealedEnvelope.seal`
(same expression, hoisted); `decodeFromDisk` keeps its exact three-way behavior (no magic →
return as-is; magic + no key → `missingEncryptionKey`; magic + key → GCM open).
`BlobStore.encryptedMagic` is now an alias of `SealedEnvelope.magic` (same bytes), so the
header-only file scan (`isEncryptedFileOnDisk`) and the `GRDBEncryptionTests` assertions are
unchanged. Existing sealed blobs/thumbnails decode with zero migration. A pinned-bytes test
(`SealedEnvelopeTests.magicMatchesBlobStoreFormat`) makes the on-disk format a test invariant.

## 2. CKAsset staging: deliberately NOT sealed — decision + reasoning

The cross-cutting theme lists CKAsset staging as a `SealedEnvelope` call site. **Verified
conclusion: sealing the staged file would break sync, so it is intentionally excluded.**

- CloudKit uploads the staged file's bytes **verbatim** as the asset payload (`CKAsset(fileURL:)`
  is read at batch-send time). A sealed staging file would upload *ciphertext under this
  device's local blob key* as the clip's content.
- `ClipRecordMapper.decode` reads the **fetched** asset via `asset.fileURL` +
  `Data(contentsOf:)` from CloudKit-managed storage — on the receiving device that file contains
  whatever bytes were uploaded. Unsealing there cannot work: the receiving device does not share
  the sender's local blob key, and even on the same device the fetched copy is CloudKit's, not
  the staged file.
- Defense-in-depth is already adequate on this path: CloudKit encrypts CKAsset payloads in
  transit and at rest server-side, and A-1's staging lifecycle bounds the local plaintext window
  (dedicated `tmp/gancho-ck-assets/` dir, per-record deletion on the sent-record event in
  `CKSyncEngineAdapter`, start-time sweep of files older than 1 h).

The decision is documented in code in `ClipRecordMapper.swift`'s "CKAsset staging" comment block
so a future pass doesn't "fix" it into a sync-breaking seal. No functional change to
`ClipRecordMapper`; `CKSyncEngineAdapter` untouched (owned elsewhere).

## 3. A-8 — SharedInbox deposits are sealed (`ClipboardCore/SharedInbox.swift`)

- `SharedInbox.init(directory:key:)` and `inAppGroup(key:)` gain an **optional** `key: Data?`
  (default `nil`) — the store's blob encryption key. Fully back-compatible: every existing call
  site (`ShareViewController`, `GanchoiOSApp`, tests) compiles unchanged.
- `deposit` now sealing-aware: encode JSON → `SealedEnvelope.seal` when a key is present → write.
  Without a key behavior is plaintext as before, but the doc comments state production callers
  should always pass the key.
- `drainPrepared` unwraps via a private `openedPayload`: sealed files open with the key; a sealed
  file with no/wrong key is discarded as poison (same policy as unreadable JSON — the inbox never
  wedges); **unsealed bytes pass through**, so both legacy plaintext `PreparedCapture` files and
  the even older bare-`PasteboardCapture` files still drain — an in-flight share survives the
  update, exactly like the existing pre-envelope tolerance.
- **FileProtection belt-and-suspenders:** the write now uses
  `[.atomic, .completeFileProtectionUntilFirstUserAuthentication]`
  (`Data.WritingOptions`, available macOS 11+/iOS — package floor is 26/26).
  `UntilFirstUserAuthentication` (not `.complete`) because drains can run from a background
  activation after first unlock.

## 4. Tests

- `GanchoKitTests/SealedEnvelopeTests.swift` [NEW]: round-trip + plaintext-not-in-ciphertext;
  wrong key throws; single flipped ciphertext bit throws (GCM auth); plaintext pass-through;
  `isSealed` bounds; magic pinned to `BlobStore`'s bytes.
- `ClipboardCoreTests/SharedInboxTests.swift` [EXTENDED]: keyed deposit is sealed on disk (not
  decodable as plaintext JSON, content needle absent) and drains back equal; keyed inbox drains
  both legacy plaintext formats; sealed file in a key-less inbox is discarded without wedging.
  All pre-existing tests untouched and still valid (key defaults to nil).

## 5. App-side follow-up (out of scope here — `Apps/**` owned elsewhere)

The engine API is ready; the wiring is a one-line change per call site once the app owners pick
it up: `ShareViewController` (deposit side) and `GanchoiOSApp.drainSharedInbox` /
`IPadSplitView` (drain side) currently call `SharedInbox.inAppGroup()` with no key. Both
processes already read the shared-keychain SQLCipher passphrase to open the encrypted store, so
they should derive the blob key the same way the store does
(`BlobStore.encryptionKeyData(for:)` — 64-hex decodes raw, otherwise SHA-256 of the trimmed
passphrase) and pass it: `SharedInbox.inAppGroup(key: blobKey)`. Until both sides pass the key,
deposits stay legacy-plaintext (still drainable); once the extension passes it, the app side
MUST pass it too or sealed files will be discarded as poison — ship both call sites in the same
release. After that lands, `docs/SECURITY-MODEL.md`'s "exactly four places" claim holds by
construction for the share path.
