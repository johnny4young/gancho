# Store recovery and process ownership

The complete database, WAL/SHM, interrupted encrypted export, blobs and thumbnails
are preserved as one journaled, resumable unreadable generation. Fresh-key recovery
never reuses an old sealed-blob namespace.

## Suspension-safe ownership

The stable `.store-ownership.sqlite` sidecar contains only process IDs and random
process/operation UUIDs, never clip content, blob hashes, paths from clips, or keys.
It is outside the preserved blob/database generation. Its versioned metadata schema
uses WAL. Short synchronous writer transactions atomically acquire, downgrade, or
release logical claims; no new application-owned file lock or coordinator
transaction is held during pool lifetime, filesystem moves, blob work, or `await`.

A shared generation registration is retained by the store and each actual SQLite
writer/reader/snapshot connection. Configuration preparation captures it weakly
and fails closed if it is gone. A private per-connection SQL function owns one ARC
reference through SQLite's `sqlite3_create_function_v2` destructor; its scalar
callback returns NULL and no application query or persisted schema uses it. The
destructor drops only that connection's reference after SQLite closes its pager,
including delayed `close_v2` zombie completion. Configuration/watchdog objects may
survive without over-pinning a closed connection. Registration failure also invokes
the destructor, so there is no second release on the failure path. See the
[SQLite function lifetime contract](https://www.sqlite.org/c3ref/create_function.html)
and [close contract](https://www.sqlite.org/c3ref/close.html). SQLCipher builds use
SQLCipher C symbols, not system SQLite functions on SQLCipher pointers. Exclusive recovery conflicts with all generation and blob
claims. Registration precedes inspecting the journal/header. Pending recovery or
plaintext/absent database conversion requires exclusive ownership; the journal is
rechecked after acquiring it. The claim remains exclusive through the namespace
change and pool initialization, then downgrades to a shared registration. A failed
or interrupted move keeps its journal; the next exclusive owner resumes it before
any new pool can open that generation.

On iOS, `DatabaseSuspension.suspend()` fences and finishes coordinator metadata
transactions before posting GRDB suspension, and rejects new coordinators opened
after that boundary. Coordinator connections also observe GRDB suspension. Logical
claims remain committed while suspended, without keeping a kernel lock. Release
uses the exact operation and process UUID; a failed/suspended release is retained
for a bounded resume cleanup pass or the next operation at that directory.
Coordinator connection close/checkpoint is also fenced; suspended/busy releases
retain their queues until safe cleanup, rather than relying on deinitialization. Only
known-finished operations enter this retry set. Cancellation never releases an
operation before its protected transaction/work has finished.

Every claim is stamped with the kernel boot session (`kern.bootsessionuuid`) and,
where `sysctl(KERN_PROC_PID)` reports it, the claimant's process start time. A
claim is reclaimed only on positive evidence:

- its boot session differs from the current one (claims never survive a reboot,
  and PIDs restart at boot, so this covers the most common reuse case);
- `kill(pid, 0)` reports `ESRCH`, which Apple's [iOS kill(2) manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kill.2.html)
  defines as absence of the process; or
- the PID can be signalled (`kill` succeeds) and its current start time differs
  from the recorded one, i.e. the PID now belongs to another process.

Unknown stamps (an unavailable sysctl, or a claim migrated from the version-1
ledger), permission/sandbox failures, unknown errors and processes whose start
time cannot be read remain fail-closed; malformed stamps fail the ledger closed.
UUID mismatch, elapsed time, missing heartbeats and suspension are never evidence
of death. Recovery returns busy immediately; async blob ownership has a bounded
wait. Within one boot, a claim whose PID was reused by a process this one may not
signal (another user's, or another sandboxed app's on iOS) still withholds
availability until that PID is provably absent. No destructive
timeout/forced-reclamation path is provided. The user-facing caller must report
busy/error, not silently reset.

The ledger is versioned with `user_version`. Version 2 adds the
`owner_identity` table beside `owner`; a version-1 ledger is migrated in place by
creating that table, and its existing claims keep their PID-only judgement. A
missing table, an unknown version or an altered schema still fails closed and is
never recreated.

## Compatibility and qualification boundary

The main schema and sealed data format are unchanged. Older binaries ignore the
sidecar and do not participate in this protocol. Absence of registrations does not
prove an old pool is closed. Ownership safety therefore requires a quiescent,
coordinated upgrade/restart of every participant (app, extensions, CLI, MCP and
maintenance tools). Mixed-version writers or recovery are not qualified; rollout
must stop older participants before enabling the new recovery/cleanup paths. The
optional raw-key rekey remains separately gated by its existing opt-in and
quiescent/device rollout requirements; this repair does not qualify that migration.

Deterministic metadata/state tests prove atomic claims, scope conflicts, exact-token
release, exited/unverifiable/reused identity policy, deferred cleanup and WAL idle
writes. They do not prove iOS sandbox liveness behavior or physical-device jetsam
avoidance. iOS app/keyboard/share/widget suspension, expiration, restart and reboot
stress across real App Group processes remain release gates. See Apple's
[TN2408](https://developer.apple.com/library/archive/technotes/tn2408/_index.html)
and [DTS suspension discussion](https://developer.apple.com/forums/thread/655225).

The global suspension-notification seam should run in an isolated/serial iOS test
invocation; suite-local serialization does not isolate it from other test suites.
The deterministic ownership tests use independent injected lifecycle objects.
