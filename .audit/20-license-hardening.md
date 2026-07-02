# 20 — License hardening: token expiry + install binding (A-3)

**Date:** 2026-07-02 · **Scope:** implements `.audit/14` finding A-3 — the direct-download
license token carried only `licenseID` + `issuedAt`, so one signed token unlocked Pro on
unlimited machines forever. This change adds **optional** expiry and install-binding
constraints to the token format, enforced at verification, without invalidating any token
already in the field.

## What changed

| File | Change |
|---|---|
| `Packages/GanchoKit/Sources/GanchoKit/License.swift` | `LicenseToken` gains `expiresAt: Date?` and `boundFingerprint: String?` (both defaulted in `init`, so `LicenseToken(licenseID:issuedAt:)` still compiles everywhere). `LicenseVerifier.verify` gains defaulted `now: Date = Date()` and `fingerprint: String? = nil` parameters and, **after** the signature holds and the payload decodes, rejects a token whose `expiresAt` is in the past or whose `boundFingerprint` differs from the caller's fingerprint (including when the caller offers none — fail closed). |
| `Packages/GanchoKit/Sources/GanchoKit/LicenseActivation.swift` | `LicenseActivationService` gains opt-in issuance knobs: `tokenLifetime: TimeInterval? = nil` (mints `expiresAt = issuedAt + lifetime`) and `fingerprintProvider: @Sendable () -> String? = { nil }` (mints `boundFingerprint`). The defaults mint exactly today's lifetime, unbound token — nothing regresses. |
| `Packages/GanchoKit/Sources/GanchoKit/LicenseTokenStore.swift` | New `LicenseFingerprint.current(in:)` — the stable per-install identifier a token can be bound to (design below). |
| `Packages/GanchoKit/Tests/GanchoKitTests/LicenseTests.swift` | New tests: expired rejected / unexpired accepted; fingerprint match accepted / mismatch and missing rejected; **hand-built legacy payload** (only the original two keys) still verifies with nil constraints; constrained sign→verify round-trip; fingerprint stability per store. |
| `Packages/GanchoKit/Tests/GanchoKitTests/LicenseActivationTests.swift` | New test: issuance opting into `tokenLifetime` + `fingerprintProvider` mints a token that verifies only before expiry and on the matching install. |

`LicenseSigner` needed no change: it signs whatever payload the token encodes to, so the new
fields ride along automatically when issuance sets them.

## Why every existing token keeps working (forward compatibility)

The verification pipeline is: **check the Ed25519 signature over the exact received payload
bytes → decode those same bytes → enforce the token's own constraints**. Nothing re-encodes
the payload, so:

1. **Signature:** an existing token's signature covers its own bytes — a JSON object with
   only `issuedAt` and `licenseID`. Those bytes are untouched by this change; the signature
   still validates.
2. **Decode:** `expiresAt`/`boundFingerprint` are `Optional`, and Swift's synthesized
   `Decodable` uses `decodeIfPresent` for optionals — a payload lacking the keys decodes with
   `nil`s, not an error.
3. **Constraints:** `nil` means "no constraint". `verify` only rejects when a field is
   present and violated, so a legacy token passes both checks unconditionally — identical
   observable behavior to today.

The symmetric property holds on the minting side: synthesized `Encodable` uses
`encodeIfPresent`, so a default-minted token (nil constraints) produces a payload with the
same two keys as before — byte-identical shape under the deterministic sorted-keys/ISO-8601
encoder. New-format and old-format tokens are therefore indistinguishable until issuance
opts in.

This is pinned by the `legacyTokenStillUnlocks` test, which signs a **hand-written** two-key
JSON payload (exactly what the pre-hardening app produced) and asserts it verifies and
decodes with nil constraints.

## Fingerprint design and its limits

`LicenseFingerprint.current(in:)` returns the SHA-256 hex digest of a **random UUID minted
on first use** and persisted in the Keychain (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`,
service `com.johnny4young.gancho.license`, account `install-fingerprint`, never
iCloud-synchronised). Deliberately **no hardware identifiers and no IOKit** — no privacy
surface, no entitlement requirements, portable across platforms.

Consequences, accepted by design:

- It binds a token to the **install**, not the hardware. It survives relaunches and app
  updates; it survives a reinstall only as long as the Keychain item does.
- If the Keychain item is wiped, a fresh fingerprint is minted and a previously-bound token
  stops verifying → the user re-activates their Lemon Squeezy key (each machine already
  activates its own seat, so this is the existing recovery path). **Fail closed, never
  fail open.**
- An attacker who can copy the token can in principle also copy the Keychain fingerprint
  item — this raises the sharing bar from "paste one string" to "extract and replant a
  device-only Keychain item", which is the honest ceiling for a fully-offline scheme. Real
  revocation still requires the (soft) online re-validation noted in A-3.
- If the first-use Keychain **write** fails, the fresh value is still returned so activation
  can proceed; the fingerprint just isn't stable until the Keychain heals (bound tokens then
  fail closed at next verify — never a silent unlock).

## Issuance-side follow-up (for this to bite)

The verification code is ready today, but **every token currently minted is still lifetime
and unbound** — the constraints are opt-in at issuance. To activate the hardening:

1. **Lemon Squeezy issuance opts in:** construct `LicenseActivationService` with
   `tokenLifetime:` (e.g. a re-validation horizon rather than a hard license end) and
   `fingerprintProvider: { LicenseFingerprint.current() }` at the app's composition root
   (`Apps/GanchoMac/AppModel.swift`, `makePurchaseHandler()` — out of scope for this change).
2. **Verification call sites pass the fingerprint:** `LicenseKeyPurchaseHandler` (out of
   scope here) calls `verifier.verify(token)` with defaults; once bound tokens exist it must
   pass `fingerprint: LicenseFingerprint.current()` in `currentTier()` / `activateResult`,
   or bound tokens will be rejected on that machine (fail closed — safe, but locks the
   feature out until wired).
3. **Soft online re-validation** against Lemon Squeezy for expiring tokens (re-mint on
   success), keeping the works-offline property by only soft-gating — per A-3's
   prescription; not implemented here.

Until (1) and (2) land, behavior is bit-for-bit today's: lifetime, unbound tokens that
verify offline forever. Nothing regresses; the format and enforcement are simply ready.
