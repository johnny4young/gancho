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

A shared generation registration is retained by the store and by the pool's
configuration closure. Exclusive recovery conflicts with all generation and blob
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

A positive, bounded PID is checked with `kill(pid, 0)`, which sends no signal.
Only `ESRCH` permits automatic reclamation: Apple's [iOS kill(2) manual](https://developer.apple.com/library/archive/documentation/System/Conceptual/ManPages_iPhoneOS/man2/kill.2.html)
defines that result as absence of the corresponding process. Successful checks,
permission/sandbox failures, unknown errors, malformed identities, and current
live PIDs reused after exit or reboot remain fail-closed. UUID mismatch, elapsed
time, missing heartbeats, and suspension are never evidence of death. Recovery
returns busy immediately; async blob ownership has a bounded wait. A stale claim
whose PID is reused or whose liveness cannot be established may withhold availability
until that PID is provably absent. No destructive timeout/forced-reclamation path
is provided. The user-facing caller must report busy/error, not silently reset.

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
