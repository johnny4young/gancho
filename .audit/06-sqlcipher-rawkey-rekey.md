# 06 — SQLCipher raw-key adoption (kill the per-connection PBKDF2)

**STATUS: SPECIFICATION + TESTS ONLY. NOTHING IN THIS DOSSIER IS APPLIED.**
The encryption path is the single most dangerous surface in the app — a wrong
key or migration change makes every user's store unreadable, which is
irreversible data loss. Everything below is written to be pasted in *after*
the goal-A signposts (now landed, see §8) have confirmed on a real device that
the KDF is in fact the dominant launch cost, and after the test file in §6 is
green on macOS and the iOS simulator.

Grounded in file:line as of branch `claude/gancho-engineering-audit-byfy24`,
and in the actual GRDB fork sources at the pinned revision
(`johnny4young/GRDB.swift @ 77e27afdf29bc298a14d2b19e2bb5bcf466df632`,
verified by reading the fork, not from memory).

---

## 1. Verified ground truth

### 1.1 What the app does today

- `GRDBClipboardStore.convenience init(directory:passphrase:)`
  (Packages/GanchoKit/Sources/GanchoKit/GRDBClipboardStore.swift:32-73) keys
  every pool connection via
  `configuration.prepareDatabase { try db.usePassphrase(passphrase) }`
  (GRDBClipboardStore.swift:49-51).
- The passphrase is a **64-character lowercase hex string** — 32 random bytes
  from `SecRandomCopyBytes`, hex-encoded
  (KeychainPassphraseStore.swift:153-160, `generateKey()`).
- `BlobStore.encryptionKeyData(for:)` (BlobStore.swift:38-46) **decodes that
  same 64-hex string directly to the 32-byte blob key**. This is a load-bearing
  coupling: whatever changes about the SQLCipher key *format*, the string
  handed to `BlobStore.encryptionKeyData` must remain the plain hex, or every
  sealed blob and thumbnail becomes unreadable.
- The plaintext→encrypted migration `encryptPlaintextStoreIfNeeded`
  (GRDBClipboardStore.swift:103-136) attaches a sibling with
  `ATTACH DATABASE '…' AS encrypted KEY '<hex-as-string-literal>'` — a *string*
  literal, so the sibling is keyed through the KDF as well.

### 1.2 What the fork actually exposes (read, not assumed)

`GRDB/Core/Database+SQLCipher.swift` in the fork defines, under
`#if SQLITE_HAS_CODEC`:

- `func usePassphrase(_ passphrase: String) throws` → UTF-8 bytes →
  `usePassphrase(_ passphrase: Data)` → **`sqlite3_key(sqliteConnection,
  bytes, count)`**.
- `func changePassphrase(_ passphrase: String) throws` → UTF-8 bytes →
  `changePassphrase(_ passphrase: Data)` → **`sqlite3_rekey(...)`**, carrying
  an upstream `FIXME` that Zetetic discourages `sqlite3_rekey` in favor of
  `sqlcipher_export` (§4 weighs this for our case).
- `Database.setUp()` (fork Database.swift:509-527) runs, in order:
  `validateSQLCipher()` (a `PRAGMA cipher_version`, key-independent) →
  `configuration.setUp(self)` (this is where `prepareDatabase` runs
  `sqlite3_key` — **no I/O yet**) → `validateFormat()` — the first real page
  read, which is where a wrong key surfaces.
- `Database.checkpoint(_:on:)` (fork Database.swift:1144) with
  `CheckpointMode.truncate` (fork Database.swift:2040-2053).
- `Configuration.readonly` (Configuration.swift:42),
  `Configuration.observesSuspensionNotifications` (Configuration.swift:131),
  `Configuration.busyMode` (Configuration.swift:331).
- The fork links Zetetic's official `sqlcipher/SQLCipher.swift` ≥ 4.11.0
  (fork Package.swift:41-46).

### 1.3 The SQLCipher raw-key rule (why this works at all)

SQLCipher inspects the key material handed to `sqlite3_key`/`sqlite3_rekey`
(and `PRAGMA key`/`PRAGMA rekey`): if the text is **exactly a BLOB literal of
the form `x'<64 hex digits>'`** it uses the decoded 32 bytes as the raw AES
key and **skips PBKDF2 entirely** (the 96-hex variant additionally pins the
16-byte salt; we don't need it — the salt stays in the file's first 16 bytes,
which is also why an encrypted gancho.sqlite has no plaintext header,
GRDBClipboardStore.swift:110-112 relies on that). Any *other* text — including
today's bare 64-hex string, and including the 32 raw bytes passed through the
`usePassphrase(Data)` overload — is treated as a passphrase and run through
PBKDF2-HMAC-SHA512 at 256,000 iterations. **The `Data` overload is a footgun,
not a shortcut: raw bytes ≠ raw key.**

So the raw-key open for this fork is simply:

```swift
configuration.prepareDatabase { db in
    try db.usePassphrase("x'\(hex64)'")   // BLOB-literal text → sqlite3_key → no KDF
}
```

No `db.execute(sql: "PRAGMA key = …")` needed: `usePassphrase` already routes
through `sqlite3_key`, which honors the literal form; staying on the fork's
supported API also keeps key material out of SQL-string plumbing. And the
rekey is `try db.changePassphrase("x'\(hex64)'")` — same literal rule via
`sqlite3_rekey`.

**But it is a different effective key.** Existing databases are encrypted
with `KDF(hex-string)`. Flipping the open form without migrating bricks every
existing install. Hence everything below.

---

## 2. Design: the safe open path (no lockout, no marker)

```
open(directory, passphrase):
  1. encryptPlaintextStoreIfNeeded            (unchanged trigger; now exports
                                               straight to a RAW-keyed sibling, §3.3)
  2. key = resolvedSQLCipherKey(path, passphrase, allowMigration)
       a. passphrase not 64-hex           → use passphrase (KDF, today's path)
       b. file missing (fresh install)    → raw key (pool creates it raw)
       c. raw key opens (cheap probe)     → raw key            ← steady state
       d. allowMigration and the derived
          key opens                       → checkpoint → rekey → checkpoint
                                            → verify raw opens → raw key
       e. anything else                   → derived passphrase (pool open
                                            below fails closed on a truly
                                            wrong key, exactly like today)
  3. DatabasePool(path, prepareDatabase: usePassphrase(key))
  4. BlobStore key: ALWAYS BlobStore.encryptionKeyData(for: passphrase) —
     the plain hex string, never the x'…' literal.
```

Decisions, with reasons:

- **Raw-first probe instead of a persisted marker.** The prompt for this work
  suggested a one-way marker so future opens skip the probe. Deliberately
  rejected: the raw-first *attempt is* the open — on an already-migrated
  database it succeeds immediately with **no KDF and no second open of the
  pool**, so there is nothing meaningful to skip (the probe is one extra
  `DatabaseQueue` open + a single keyed page read, microseconds). A marker,
  by contrast, is state that can disagree with the file it describes — Time
  Machine / iCloud-backup restores, App Group container restores, and
  `.ganchoarchive`-adjacent manual file surgery can each produce
  marker-without-migrated-DB or migrated-DB-without-marker. If the marker is
  trusted ("skip the derived fallback"), the mismatch is a **user lockout**;
  if it is not trusted, it saved nothing. The file's own keying is the only
  ground truth, and probing it is nearly free.
- **In-place `sqlite3_rekey` (via `changePassphrase`) instead of
  `sqlcipher_export` into a sibling + file swap**, despite the fork's FIXME.
  The export-swap (the `encryptPlaintextStoreIfNeeded` pattern) **unlinks the
  live inode**. This store is opened concurrently by the iOS app, keyboard,
  widgets, share extension, and the macOS app + CLI over an App Group /
  shared directory. A sibling process holding an open `DatabasePool` across
  the swap keeps file descriptors to the *deleted* inode; its later writes
  land in the orphaned file and are **silently lost** when it closes. (The
  plaintext migration tolerates this only because it predates multi-process
  reality and runs once ever, on stores that had no extensions reading them;
  that latent hazard is noted in §7/R8.) `sqlite3_rekey` rewrites pages
  through the pager on the *same* inode, inside SQLite's own locking, and an
  interrupted rekey rolls back through the journal — sibling processes are
  serialized, not stranded. Zetetic's general preference for
  `sqlcipher_export` is about changing cipher *settings* and
  plaintext↔encrypted conversions, which rekey cannot do; a pure key swap is
  exactly what `sqlite3_rekey` is for.
- **WAL discipline around the rekey**: `checkpoint(.truncate)` immediately
  before (folds every derived-key WAL frame into the main file and empties
  the WAL) and immediately after (folds the re-keyed pages the rekey itself
  wrote into the WAL, and truncates it) — so after the migration **no frame
  encrypted with the old key exists anywhere**, and the `-shm` file (an
  uncrypted index, never key material) is coherent. If either checkpoint or
  the rekey fails (busy sibling reader, iOS suspension), the migration is
  abandoned *without* error: the store opens with the derived key this
  launch and retries next open. **Verification item (cannot be checked in
  this container):** confirm on-device that `sqlite3_rekey` completes and
  round-trips in WAL mode on SQLCipher 4.11. If it does not, the documented
  detour is: `checkpoint(.truncate)` → `PRAGMA journal_mode = DELETE` →
  `changePassphrase(raw)` → `PRAGMA journal_mode = WAL` → checkpoint — still
  same-inode, still journal-protected.
- **Rekey only after a successful derived-key open.** The single most
  important safety property: we never call `changePassphrase` on a database
  we could not read. A wrong key fails the raw probe *and* the derived open,
  so `resolvedSQLCipherKey` returns the passphrase and the pool open fails
  closed exactly as today (`keyGatesAccess`, GRDBEncryptionTests.swift:135).
- **Extensions don't migrate.** `allowingRawKeyMigration: false` for the
  keyboard/widget/share `IntentStore.open()` path: their time/memory budgets
  are tight and a large-history rekey is a full-database rewrite. They open
  raw when the DB is already migrated, derived otherwise (no regression),
  and the main app performs the one-time rekey on its next launch.
- **Lost-race retry.** If process A rekeys between B's failed raw probe and
  B's derived attempt, B's derived attempt fails `SQLITE_NOTADB`; B re-probes
  raw once and wins. Without the retry, B would fall to the in-memory store
  for one session — not data loss, but avoidable.

### Detecting the auth failure with GRDB, precisely

With SQLCipher 4 (per-page HMAC on), a wrong or wrong-form key makes the very
first page read fail as **`SQLITE_NOTADB` (26, "file is not a database")**.
In GRDB that surfaces as a thrown `DatabaseError` from the
`DatabaseQueue`/`DatabasePool` **initializer** itself, because
`Database.setUp()` → `validateFormat()` performs a read on connect (the
`prepareDatabase` key call is I/O-free; nothing fails until that read). So:

```swift
catch let error as DatabaseError where error.resultCode == .SQLITE_NOTADB
```

is the "wrong key (or wrong key form)" signal. Anything else
(`SQLITE_BUSY`, `SQLITE_CANTOPEN`, `SQLITE_READONLY_*`, interrupts) is
environmental: the probe treats it as "not proven raw" and the migration
treats it as "not now" — both degrade to the derived key, never to a rekey.

### iOS suspension (`observesSuspensionNotifications` / `DatabaseSuspension`)

The pool sets `configuration.observesSuspensionNotifications = true` on iOS
(GRDBClipboardStore.swift:37-44) and the app posts suspend/resume at the
scene boundary (GanchoiOSApp.swift `.onChange(of: scenePhase)`,
DatabaseSuspension.swift:16-29). The migration connection must mirror the
flag: if the app is backgrounded mid-rekey, GRDB interrupts the write
(`SQLITE_INTERRUPT`/`SQLITE_ABORT`) instead of holding a lock into suspension
(0xDEAD10CC). An interrupted rekey rolls back via the journal; the store
opens derived on resume and the migration retries on the next cold open.
Ordering note: the migration runs inside the store `init`, which the app
performs at foreground launch — *after* `DatabaseSuspension.resume()` — so
the common case never races the boundary.

---

## 3. Ready-to-paste Swift (NOT applied)

All of it goes into `Packages/GanchoKit/Sources/GanchoKit/GRDBClipboardStore.swift`
inside the existing `#if SQLITE_HAS_CODEC` regions. No logging anywhere
(NoContentLoggingTests sweeps this file). Comments stay content-free.

### 3.1 New helpers

```swift
#if SQLITE_HAS_CODEC
    /// The SQLCipher raw-key BLOB literal (`x'<64 hex>'`) for a 256-bit hex
    /// passphrase, or nil when the passphrase is not exactly 64 hex digits
    /// (arbitrary passphrases keep the PBKDF2 behavior).
    ///
    /// SQLCipher treats key text in exactly this form — passed through
    /// `sqlite3_key`/`sqlite3_rekey`, which is what `usePassphrase` and
    /// `changePassphrase` call — as raw key material and skips the KDF.
    /// Any other text (including the bare 64-hex string, and including raw
    /// bytes via the `usePassphrase(Data)` overload) is KDF-derived.
    static func rawKeyLiteral(for passphrase: String) -> String? {
        let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 64, trimmed.allSatisfy(\.isHexDigit) else { return nil }
        return "x'\(trimmed)'"
    }

    /// Decides which SQLCipher key form actually opens the database at
    /// `path`, migrating a legacy KDF-derived database to the raw key in
    /// place when allowed. Total (never throws): a truly wrong key keeps
    /// today's fail-closed behavior at the pool open.
    static func resolvedSQLCipherKey(
        at path: String, passphrase: String, allowingRawKeyMigration: Bool
    ) -> String {
        guard let rawKey = rawKeyLiteral(for: passphrase) else { return passphrase }
        // Fresh install: no file yet — the pool below creates it raw-keyed.
        guard FileManager.default.fileExists(atPath: path) else { return rawKey }
        // Steady state: one cheap keyed read (no KDF) proves the raw key.
        if opensWithKey(path: path, key: rawKey) { return rawKey }
        guard allowingRawKeyMigration else { return passphrase }
        if rekeyToRawKey(at: path, passphrase: passphrase, rawKey: rawKey) {
            return rawKey
        }
        // Raced a sibling process that migrated between our probe and our
        // derived open? One re-probe settles it.
        if opensWithKey(path: path, key: rawKey) { return rawKey }
        // Not migrated this launch (busy sibling, suspension, wrong key):
        // open with the legacy derived key; retry next open.
        return passphrase
    }

    /// One keyed, read-only page read. False means "not this key" OR any
    /// environmental failure — callers only ever treat true as proof.
    private static func opensWithKey(path: String, key: String) -> Bool {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.prepareDatabase { db in
            try db.usePassphrase(key)
        }
        guard let queue = try? DatabaseQueue(path: path, configuration: configuration)
        else { return false }
        defer { try? queue.close() }
        return (try? queue.read { db in
            try Row.fetchOne(db, sql: "SELECT name FROM sqlite_master LIMIT 1")
        }) != nil
    }

    /// One-time, in-place migration: KDF-derived key → raw key, on the SAME
    /// inode (sibling processes with open pools are serialized by SQLite's
    /// locking, never stranded on an unlinked file).
    ///
    /// Fail-safe by construction: the database is only re-keyed after a
    /// successful open with the legacy derived key, and `sqlite3_rekey` is
    /// journal-protected — an interruption (busy reader, iOS suspension)
    /// rolls back and the store keeps opening with the derived key until a
    /// later launch completes the migration.
    private static func rekeyToRawKey(
        at path: String, passphrase: String, rawKey: String
    ) -> Bool {
        var configuration = Configuration()
        configuration.busyMode = .timeout(2)
        #if os(iOS)
            // Mirror the pool: release locks instead of dying with
            // 0xDEAD10CC if iOS suspends the app mid-rekey.
            configuration.observesSuspensionNotifications = true
        #endif
        configuration.prepareDatabase { db in
            try db.usePassphrase(passphrase)  // the legacy derived form
        }
        guard let queue = try? DatabaseQueue(path: path, configuration: configuration)
        else { return false }  // wrong key or busy — leave the file alone
        defer { try? queue.close() }
        let rekeyed: Bool = (try? queue.writeWithoutTransaction { db in
            // Fold every derived-key WAL frame into the main file first, so
            // no frame encrypted with the old key survives the switch…
            try db.checkpoint(.truncate)
            try db.changePassphrase(rawKey)  // sqlite3_rekey: in place, journaled
            // …and fold the re-keyed pages, leaving an empty WAL.
            try db.checkpoint(.truncate)
            return true
        }) ?? false
        guard rekeyed else { return false }
        // Paranoia over trust: only report success if the raw key now
        // actually opens the file.
        return opensWithKey(path: path, key: rawKey)
    }
#endif
```

### 3.2 The keying block in `convenience init` (replaces lines 46-58)

The initializer grows one defaulted parameter so extensions can opt out of
performing the migration (they still *read* raw-keyed stores):

```swift
public convenience init(
    directory: URL, passphrase: String? = nil, allowingRawKeyMigration: Bool = true
) throws {
```

```swift
        let blobEncryptionKeyData: Data?
        #if SQLITE_HAS_CODEC
            if let passphrase {
                try Self.encryptPlaintextStoreIfNeeded(at: dbPath, passphrase: passphrase)
                // Random 256-bit keys open with SQLCipher's raw-key form —
                // PBKDF2 over an already-random key adds latency, not
                // security. Legacy KDF-derived stores are re-keyed in place,
                // once; see resolvedSQLCipherKey.
                let sqlcipherKey = Self.resolvedSQLCipherKey(
                    at: dbPath, passphrase: passphrase,
                    allowingRawKeyMigration: allowingRawKeyMigration)
                configuration.prepareDatabase { db in
                    try db.usePassphrase(sqlcipherKey)
                }
                // The blob key derives from the PLAIN hex string — never the
                // x'…' literal — or every sealed blob/thumbnail is lost.
                blobEncryptionKeyData = BlobStore.encryptionKeyData(for: passphrase)
            } else {
                blobEncryptionKeyData = nil
            }
        #else
            blobEncryptionKeyData = nil
        #endif
```

Call-site changes: `SharedCaptureIntent.swift` `IntentStore.open()` and
`KeyboardModel` pass `allowingRawKeyMigration: false` (via a matching
parameter on `GRDBClipboardStore.encrypted(directory:keychainAccessGroup:
allowingRawKeyMigration:)`); apps and CLI keep the default `true`.

### 3.3 `encryptPlaintextStoreIfNeeded` (plaintext → raw directly)

Ordering stays: plaintext check → keying decision → pool. Because the
migration runs *before* `resolvedSQLCipherKey`, exporting the plaintext DB to
a **raw-keyed** sibling means a legacy plaintext store converges on raw in
one step instead of paying plaintext→KDF→raw. The only change is the `KEY`
expression (a BLOB literal is not quoted):

```swift
                let quotedPath = encryptedPath.replacingOccurrences(of: "'", with: "''")
                // A 64-hex key attaches with the raw-key BLOB literal (no
                // KDF, and no re-key needed afterwards); any other
                // passphrase keeps the derived string form.
                let keyExpression =
                    Self.rawKeyLiteral(for: passphrase)
                    ?? "'\(passphrase.replacingOccurrences(of: "'", with: "''"))'"
                try db.execute(
                    sql: "ATTACH DATABASE '\(quotedPath)' AS encrypted KEY \(keyExpression)")
```

The header check (GRDBClipboardStore.swift:109-112) is unaffected: raw-keyed
databases still keep the salt in the first 16 bytes, so an encrypted store
never carries the plaintext magic header (asserted today by
`encryptedStoreRevealsNothing`).

`migratesPlaintextStore` / `migratesPlaintextBlobsAndThumbnails`
(GRDBEncryptionTests.swift:158-244) keep passing unchanged — they assert
content survival and ciphertext-on-disk, not the key form.

---

## 4. Cross-process choreography (App Group reality check)

| Scenario | What happens |
|---|---|
| App rekeys while keyboard has an open pool | `checkpoint(TRUNCATE)` needs all readers parked; a live reader makes it (or the rekey) return busy → migration abandoned, app opens derived, retries next launch. If the keyboard is idle-but-open, SQLite's locking serializes the rekey; the keyboard's *next* statement on old connections fails (`SQLITE_NOTADB` on page HMAC) and the keyboard reopens — its open path probes raw first and succeeds. This is the roughest edge: see R2 and the on-device test matrix (§7). |
| Keyboard opens while app is mid-rekey | Keyboard's raw probe / derived open block on the write lock up to its busy timeout, then fall to derived → NOTADB → in-memory for that invocation (worst case, one keyboard session without history) or simply succeed post-rekey via the retry probe. |
| Two processes race the migration | Both hold `busyMode: .timeout`; one wins the write lock and rekeys; the loser's derived open fails NOTADB → its retry probe sees raw → opens raw. |
| CLI on macOS | Same binary path (`GanchoCLI.swift` opens via the same init); the embedded CLI ships in the app bundle so it updates atomically with the app. A *stale* CLI copied onto PATH manually would fail to open a migrated store (fails closed, no corruption). |

---

## 5. Rollout checklist (in order; do not compress)

1. **Measure first (done in this pass — goal A).** Instruments → os_signpost,
   subsystem `com.johnny4young.gancho`, category `Launch`: `StoreOpen` on
   iOS + macOS cold launches; MetricKit `LaunchMetrics` events for fleet
   numbers. Proceed only if `StoreOpen` is triple-digit ms and dominated by
   the pool open (App Launch template shows PBKDF2/`sqlite3_key` frames
   under `DatabasePool.init`).
2. **Land the test file (§6) plus the Package.swift test-dependency line**
   (`GanchoKitTests` needs `.product(name: "GRDB", package: "GRDB.swift")`
   added to its `dependencies: ["GanchoKit"]`, Package.swift:80-83) — tests
   must be green on macOS **and** an iOS simulator destination before any
   production change.
3. **Release N: raw-first open only — no rekey.** Ship §3.1 + §3.2 with the
   rekey call **disabled** (hard-code `allowingRawKeyMigration: false` at
   every call site, or land `rekeyToRawKey` in a follow-up): existing stores
   keep opening derived (bit-identical disk state, downgrade-safe for
   upgraders), fresh installs create raw-keyed stores. Fresh installs get the
   full win immediately; existing installs get nothing yet — that's the
   point: one release of soak proves the raw open path against real devices,
   restores, and extensions with zero migration risk.
   - Decision to make explicit: a **fresh** install on N that later
     downgrades below N cannot open its (raw-keyed) store — the apps fall
     back to the in-memory store with the existing "Couldn't open secure
     storage" banner (AppModel.swift:246-250, IOSAppModel
     `recordStorageHealthIfNeeded`); nothing is deleted, and re-upgrading
     restores access. Documented, accepted (a fresh install has minimal
     history by definition).
4. **Release N+1: enable the rekey** (apps + CLI `true`, extensions stay
   `false`). From here, **downgrading below N will not open a migrated
   store** — same banner, data intact on disk, recovered by re-upgrading.
   State this in the release notes. There is deliberately **no
   down-migration**; write it in CHANGELOG as a one-way door.
5. **Keep the fallbacks indefinitely**, not for one release: the derived-key
   fallback and the plaintext migration both guard *restored* old files
   (Time Machine, Finder backups, device migration), which can appear years
   later. They are ~40 lines and only run when probes fail.
6. **On-device verification matrix before N+1 ships:**
   - iPhone: legacy store, cold open → signpost shows one-time rekey cost,
     subsequent opens drop by the measured KDF delta; keyboard invoked
     mid-rekey and post-rekey; widget intent save post-rekey.
   - macOS: app + CLI concurrently, one migrates while the other reads.
   - Restore an old (derived) backup over a migrated install → opens via
     fallback and re-migrates.
   - `PRAGMA rekey` in WAL mode round-trips on SQLCipher 4.11 (§2's
     verification item); if not, apply the journal-mode detour and re-run.
   - Sync (CKSyncEngine), `.ganchoarchive` export/restore, retention purge:
     all unaffected (they run above the store API), but smoke them anyway.

---

## 6. Ready-to-add test file (Swift Testing) — NOT added yet

Written against the **post-change** code in §3 (it will not compile before
§3 lands — `resolvedSQLCipherKey` etc. don't exist yet, which is also your
guard against landing tests without the feature or vice versa). Drop in as
`Packages/GanchoKit/Tests/GanchoKitTests/GRDBRawKeyAdoptionTests.swift`, and
add the GRDB product to `GanchoKitTests`' dependencies (checklist item 2).

```swift
import Foundation
import GRDB
import Testing

@testable import GanchoKit

// Raw-key adoption only exists on SQLCipher builds; on a plaintext build the
// whole path compiles out and there is nothing to assert.
#if SQLITE_HAS_CODEC

    /// A 256-bit hex key, like `KeychainPassphraseStore` produces.
    private func testKey() throws -> String { try KeychainPassphraseStore.generateKey() }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-rawkey-\(UUID().uuidString)", isDirectory: true)
    }

    private func dbPath(_ dir: URL) -> String {
        dir.appendingPathComponent("gancho.sqlite").path
    }

    /// True when a single keyed, read-only page read succeeds with `key`
    /// (either the bare hex — the legacy KDF form — or the x'…' raw literal).
    private func opens(_ dir: URL, key: String) -> Bool {
        var configuration = Configuration()
        configuration.readonly = true
        configuration.prepareDatabase { db in try db.usePassphrase(key) }
        guard let queue = try? DatabaseQueue(path: dbPath(dir), configuration: configuration)
        else { return false }
        defer { try? queue.close() }
        return (try? queue.read { db in
            try Row.fetchOne(db, sql: "SELECT name FROM sqlite_master LIMIT 1")
        }) != nil
    }

    /// Builds a store keyed the LEGACY way — `sqlite3_key` over the bare hex
    /// string, i.e. PBKDF2-derived — exactly what every pre-migration install
    /// has on disk. Bypasses the production init on purpose: after the
    /// change, the production init would migrate on open.
    private func makeDerivedKeyStore(
        at dir: URL, key: String, items: [(ClipItem, ClipContent?)]
    ) async throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.prepareDatabase { db in try db.usePassphrase(key) }
        let pool = try DatabasePool(path: dbPath(dir), configuration: configuration)
        let store = GRDBClipboardStore(
            writer: pool,
            blobs: BlobStore(
                directory: dir.appendingPathComponent("blobs"),
                encryptionKeyData: BlobStore.encryptionKeyData(for: key)))
        try store.migrate()
        for (item, content) in items {
            _ = try await store.insert(item, content: content)
        }
        try pool.close()
    }

    @Suite("GRDBClipboardStore — SQLCipher raw-key adoption")
    struct GRDBRawKeyAdoptionTests {
        private static let needle = "GANCHO-RAWKEY-NEEDLE-PAYLOAD-7"
        private static let blobPayload = Data("GANCHO-RAWKEY-BLOB".utf8) + Data([0, 1, 2, 3])

        private static func fixtureItems() -> [(ClipItem, ClipContent?)] {
            var items: [(ClipItem, ClipContent?)] = (0..<10).map { index in
                let text = "\(needle)-\(index)"
                return (
                    ClipItem(
                        kind: .text, preview: String(text.prefix(120)),
                        contentHash: ClipItem.hash(of: text, kind: .text)),
                    .text(text)
                )
            }
            items.append(
                (
                    ClipItem(
                        kind: .image, preview: "Image",
                        contentHash: ClipItem.hash(of: blobPayload, kind: .image)),
                    .binary(data: blobPayload, typeIdentifier: "public.data")
                ))
            return items
        }

        @Test("A fresh store is raw-keyed from creation (no KDF form on disk)")
        func freshStoreIsRawKeyed() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()

            var store: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: key)
            let item = ClipItem(
                kind: .text, preview: "fresh",
                contentHash: ClipItem.hash(of: Self.needle, kind: .text))
            try await store?.insert(item, content: .text(Self.needle))
            store = nil  // release → pool closes and checkpoints

            #expect(opens(dir, key: "x'\(key)'"), "fresh store should open with the raw key")
            #expect(!opens(dir, key: key), "the legacy derived form must NOT open a raw store")
        }

        @Test("A legacy derived-key store is rekeyed on open with zero data loss")
        func derivedStoreIsRekeyedWithoutDataLoss() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()
            let items = Self.fixtureItems()
            try await makeDerivedKeyStore(at: dir, key: key, items: items)
            #expect(opens(dir, key: key), "fixture must start in the legacy derived form")

            // First open with the new path: migrates, then reads every row.
            var migrated: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: key)
            let migratedStore = try #require(migrated)
            #expect(try await migratedStore.count() == items.count)
            for (item, content) in items {
                #expect(try await migratedStore.content(for: item.id) == content)
            }
            migrated = nil

            // The rekey really happened: raw opens, the derived form no longer does.
            #expect(opens(dir, key: "x'\(key)'"), "store should now open with the raw key")
            #expect(!opens(dir, key: key), "the derived form must no longer open the store")

            // Second open (the steady state): raw key, every row still there,
            // blobs included (the blob key derives from the plain hex and
            // must be untouched by the SQLCipher key-form change).
            let reopened = try GRDBClipboardStore(directory: dir, passphrase: key)
            #expect(try await reopened.count() == items.count)
            for (item, content) in items {
                #expect(try await reopened.content(for: item.id) == content)
            }
        }

        @Test("A wrong key fails closed and never rekeys the store")
        func wrongKeyFailsClosedWithoutRekey() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()
            let items = Self.fixtureItems()
            try await makeDerivedKeyStore(at: dir, key: key, items: items)

            // Wrong 64-hex key: raw probe fails, derived fallback fails,
            // the open throws — and must not have touched the file.
            #expect(throws: (any Error).self) {
                _ = try GRDBClipboardStore(directory: dir, passphrase: try testKey())
            }
            #expect(opens(dir, key: key), "a failed wrong-key open must leave the store as-was")

            // The right key still opens (and migrates) with everything intact.
            let store = try GRDBClipboardStore(directory: dir, passphrase: key)
            #expect(try await store.count() == items.count)
        }

        @Test("Extensions can open a legacy store without performing the migration")
        func migrationCanBeDisallowed() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()
            let items = Self.fixtureItems()
            try await makeDerivedKeyStore(at: dir, key: key, items: items)

            var readOnlyOpen: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: key, allowingRawKeyMigration: false)
            #expect(try await readOnlyOpen?.count() == items.count)
            readOnlyOpen = nil

            #expect(opens(dir, key: key), "a no-migration open must leave the derived key")
            #expect(!opens(dir, key: "x'\(key)'"))
        }

        @Test("A pre-encryption plaintext store migrates straight to the raw key")
        func plaintextMigratesDirectlyToRawKey() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            var plaintext: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: nil)
            let item = ClipItem(
                kind: .text, preview: "carried over",
                contentHash: ClipItem.hash(of: Self.needle, kind: .text))
            try await plaintext?.insert(item, content: .text(Self.needle))
            plaintext = nil

            let key = try testKey()
            let encrypted = try GRDBClipboardStore(directory: dir, passphrase: key)
            #expect(try await encrypted.content(for: item.id) == .text(Self.needle))

            #expect(opens(dir, key: "x'\(key)'"), "plaintext should convert straight to raw")
            #expect(!opens(dir, key: key), "no intermediate derived-key state should remain")
        }
    }

#endif
```

Notes for whoever lands it:
- `opens(dir, key:)` probing while another handle is open is safe (read-only,
  one page); every `#expect` that inspects the disk closes the store first,
  mirroring the existing suite's `store = nil` discipline
  (GRDBEncryptionTests.swift:63).
- If `insert` isn't `@discardableResult` on the writer-init store path in
  your checkout, prefix with `_ =` (the existing suite calls it bare).
- These tests cannot run in the audit container (no Swift toolchain);
  they are written to the existing suite's conventions but are
  **not compile-verified**. Run `make test` on a Mac before trusting them.

---

## 7. Residual risks, ranked

| # | Risk | Severity | Likelihood | Mitigation |
|---|---|---|---|---|
| R1 | `sqlite3_rekey` misbehaves in WAL mode on this exact SQLCipher build (partial rewrite, corrupted store) | Catastrophic (data loss) | Low — rekey is journaled and verified-by-reopen before we trust it; but this is precisely the thing the container cannot test | §2 verification item; journal-mode detour; ship rekey one release after the open path (§5.3/5.4); verified-reopen gate in `rekeyToRawKey` |
| R2 | Keyboard/widget with a *live* pool across the app's rekey sees `SQLITE_NOTADB` on its old connections mid-session | Medium (one broken extension session, no data loss) | Medium on iOS | Extensions never migrate; busy-timeout makes the rekey yield to active readers; on-device matrix (§5.6) must include this exact choreography before N+1 |
| R3 | The raw-literal assumption doesn't hold on this build (e.g. a future fork rev drops the literal parsing) | High if shipped blind, **zero data loss** in practice — it fails at first open in tests, not in the field | Low | `freshStoreIsRawKeyed` fails instantly; fork is pinned by revision (Package.swift:44-46) and any bump must re-run the suite |
| R4 | Downgrade below release N cannot open a migrated store | Medium (temporary lockout, data intact) | Certain when it happens, rare that it happens | One-way door by design; documented in CHANGELOG + release notes; in-memory fallback banner already exists on both platforms |
| R5 | Restored old backups (derived or plaintext) meet a migrated install | Low | Medium over years | Fallbacks kept indefinitely (§5.5); probe order handles every mixture; `wrongKeyFailsClosedWithoutRekey` covers the never-rekey-unreadable-files invariant |
| R6 | Someone later "simplifies" `BlobStore.encryptionKeyData(for:)` input to the x'…' literal | High (all blobs/thumbnails unreadable) | Low | The literal never leaves `resolvedSQLCipherKey`/`prepareDatabase`; comment at the blob-key line (§3.2); `derivedStoreIsRekeyedWithoutDataLoss` round-trips a blob |
| R7 | Old-key WAL frames survive the migration | Low (stale frames are superseded; only a forensic concern) | Low | Double `checkpoint(.truncate)` around the rekey; abandon on any checkpoint failure |
| R8 | (Pre-existing, noted while here) `encryptPlaintextStoreIfNeeded`'s remove-then-move swap has a crash window where `gancho.sqlite` is gone but `.encrypting` exists → next open treats it as a fresh install | High, but for the legacy plaintext path only | Very low | Out of scope for this change; worth a follow-up: rename-old-aside → move-new → delete-old, plus an orphan-sibling check on open |

---

## 8. Relationship to the measurement landed in this pass (goal A)

The signposts that gate this work are now in the app layer (never in
GanchoKit): `StoreOpen` around `GRDBClipboardStore.encrypted(...)` in
`Apps/GanchoiOS/GanchoiOSApp.swift` (the `store` property's initializer) and
`Apps/GanchoMac/AppModel.swift` (init); `FirstFetch` around the first history
load on both platforms; and MetricKit launch histograms re-emitted as
signpost events on iOS (`Apps/GanchoiOS/LaunchMetricsSubscriber.swift`).
Expected before/after on the migration: `StoreOpen` drops by the full
per-connection KDF cost (est. 50–150 ms × connections; measure, don't
trust the estimate) on every process that opens the store — app, keyboard,
widget intents, CLI.
