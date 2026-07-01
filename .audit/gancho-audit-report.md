# Gancho — Full Engineering Audit & World-Class Product Roadmap

**Audit date:** 2026-07-01
**Commit audited:** `6aa34d8` (branch `claude/gancho-engineering-audit-byfy24`, base `main`, release v0.3.2)
**Reviewer role:** principal Swift/Apple-platforms engineer + security reviewer
**Method:** single continuous session, no sub-agents. Grounded in the actual source under
`Packages/GanchoKit`, `Apps/`, `Tests/`, `.github/workflows/`, `scripts/`, and `docs/`.

> **Environment caveat (read this before trusting any "gate" claim).** This audit ran on a
> Linux container with **no Swift toolchain and no Xcode** (the project requires macOS 26 +
> Xcode 26 + a SQLCipher-enabled GRDB fork; it cannot build or run here). Therefore:
> - `make test` and `make lint` **could not be executed** — findings about test/lint behavior are
>   read from the source of the test suites, not from a run.
> - `make release-check` **fails locally only because `/usr/libexec/PlistBuddy` is macOS-only**
>   (see F-7.1); the version/changelog/formula checks that precede the plist loop all passed.
> - `make site-check` **passed** (`✓ site/ structural checks passed`).
> - UI screenshots (`screencapture` / `simctl`) could not be captured — no macOS/simulator here.
>
> None of the code findings below depend on a build; each cites `file:line` and a concrete
> failure path. Where GRDB/CloudKit runtime behavior is genuinely uncertain, it is called out.

---

## 1. Executive summary (español, registro de usted)

Gancho es un proyecto notablemente maduro para su etapa: la separación de módulos, la disciplina
de privacidad (veto antes de leer, telemetría sin contenido, IA en el dispositivo) y las barreras
de calidad (gate de localización, barrido anti-logging, cobertura ≥70 %) están a un nivel poco
común en un producto pre-lanzamiento. Usted tiene una base sólida sobre la cual construir.

Los riesgos más altos no están en la lógica de captura ni en el cifrado en reposo —ambos están
bien resueltos— sino en tres bordes: **(1) la dependencia de almacenamiento cifrado** se declara
apuntando a una *rama* móvil de un *fork* personal de GRDB, lo cual es una debilidad de cadena de
suministro en la capa más sensible del producto; **(2) la exportación** (JSON/CSV y el archivo
`.ganchoarchive`) incluye por defecto los clips sensibles con su contenido completo, anulando la
protección de caducidad corta del detector de secretos; y **(3) el servidor MCP local** no
autentica a sus clientes, de modo que cualquier proceso local podría habilitar el alcance `all`.

Además hay una fuga menor de rendimiento (una lectura de base de datos síncrona en la ruta de
búsqueda semántica que bloquea un hilo de concurrencia) y algunas deudas de robustez: el gate
`release-check` no es portable fuera de macOS, y el barrido de cadenas codificadas no cubre
`Button`/`Toggle`/`.navigationTitle`, por lo que una etiqueta sin traducir podría colarse.

Las mayores oportunidades de palanca son estratégicas: profundizar la cuña de "IA privada en el
dispositivo" con funciones que los competidores (Paste, Raycast, Maccy, CleanShot, Alfred) no
pueden copiar fácilmente —"Pregúntale a tu portapapeles" y las Dev Actions—, y convertir
`GanchoKit`/`GanchoMCP` en una superficie de extensión pública. Ninguno de los hallazgos es un
bloqueante de arquitectura; son ajustes acotados antes del lanzamiento público. Este informe
prioriza cinco de ellos al final.

---

## 2. Validation gate results (actual, not assumed)

| Gate | Result here | Notes |
| --- | --- | --- |
| `make release-check` | **Fails** (`✗ …Info.plist must use $(MARKETING_VERSION), got ''`) | **False negative** — `/usr/libexec/PlistBuddy` is absent on Linux; the plists *are* correct (`$(MARKETING_VERSION)`/`$(CURRENT_PROJECT_VERSION)`), and version/CHANGELOG/formula sync all passed. See **F-7.1**. |
| `make site-check` | **Passes** (`✓ site/ structural checks passed`) | Pure shell, ran clean. |
| `make test` | **Not run** | No Swift toolchain in this environment. |
| `make lint` | **Not run** | Same. |

The design of the suites was read directly: `NoContentLoggingTests` (engine-module logging sweep),
`LocalizationTests` (bilingual + per-bundle hardcoded sweep), `PerformanceHarnessTests` (100k
harness), `GRDBEncryptionTests`, `SyncEnablementTests`, and `GanchoArchiveTests` are all present and
substantive.

---

## 3. Findings

Severity: **P0** ship-blocker · **P1** fix before public release · **P2** should-fix · **P3** nice-to-have.
Effort: **S** ≤½ day · **M** ~1–3 days · **L** >3 days.

### Part 1 — Architecture & Code Quality

| ID | Sev | Eff | Location | Finding & impact | Fix |
| --- | --- | --- | --- | --- | --- |
| F-1.1 | P2 | L | `Apps/GanchoiOS/GanchoiOSApp.swift` (2,673 lines); `Apps/GanchoMac/PanelView.swift` (1,812); `Apps/GanchoMac/AppModel.swift` (1,245) | God-files at the app edge. `GanchoiOSApp.swift` alone holds the app entry, capture intents wiring, paste-back, Smart Paste UI, export, and paywall flow. Hard to test, hard to review, easy to regress. The architecture doc's own rule ("app targets stay thin; if logic can't be tested from a SwiftPM target it's in the wrong layer") is being bent here. | Extract view models and flow coordinators into `@MainActor` types that can be unit-tested; split the iOS file per feature surface (History, Library, Intelligence, Settings, Paywall). Move any residual non-UI logic into `GanchoKit`. |
| F-1.2 | P3 | S | `Packages/GanchoKit/Package.swift:2-7` | Header comment says "Four library products" and lists only 4; the manifest ships **7 libraries + a CLI**. Doc drift inside the source of truth new contributors read first. | Update the comment to enumerate all seven products + `gancho`. |
| F-1.3 | P2 | M | `Apps/GanchoMac/ClipThumbnailStore.swift` & `Apps/GanchoiOS/ClipThumbnailStore.swift` | Near-duplicate thumbnail-cache logic across the two apps (60/61 lines). Divergence risk (a fix applied to one, missed on the other). | Hoist the shared cache into `GanchoDesign` or `GanchoKit` with platform-typealiased `Image`, leaving only the platform image bridge at the edge. |
| F-1.4 | P2 | S | `Packages/GanchoKit/Sources/GanchoKit/MCPAccess.swift:94` (`MCPClipStore`), `SyncLocalStore.swift:11` | **Good seam, note for the record.** DI boundaries for MCP and Sync are clean protocols implemented on `GRDBClipboardStore` in-module — this is exactly the testability seam the prompt asks about, and it holds. No change; keep it. | — |
| F-1.5 | P2 | M | `GRDBClipboardStore` surface (public API) | For the README's "future non-Apple clients" goal, the public store API leaks GRDB-shaped assumptions in a few places (e.g. `thumbnailURL` semantics tied to plaintext-vs-encrypted). A third-party client would import `GanchoKit` and inherit these. The **versioned export envelope** (`GanchoArchive` v1, `ExportDocument.version`) is the right portability primitive and is already in place. | Before opening the API, freeze a documented "client contract" subset (`ClipboardStore` + `GanchoArchive` + `SyncEngine`) and mark GRDB-specific helpers `@_spi`/internal. |

### Part 2 — Performance & Optimization

| ID | Sev | Eff | Location | Finding & impact | Fix |
| --- | --- | --- | --- | --- | --- |
| F-2.1 | P2 | S | `Packages/GanchoKit/Sources/GanchoKit/SemanticSearch.swift:24` | The first DB read in `semanticSearch` uses the **synchronous** `try writer.read { … }` inside an `async` function, while the join-back read on line 56 correctly uses `try await writer.read`. The sync form blocks a Swift-concurrency cooperative thread for the duration of the scan — under load this can stall unrelated tasks. | Change to `try await writer.read`. **Fixed in this PR** (one-token, matches the sibling call). |
| F-2.2 | P2 | M | `SemanticSearch.swift:39-54` | The persistent semantic path decodes every stored vector into a fresh `[Float]` and computes cosine with a scalar `for`-loop (`dot`/`norm`), allocating per row. `EmbeddingIndex` already has the Accelerate (`vDSP_dotpr`) implementation — the DB path doesn't use it. Fine at ≤10k vectors (the documented budget) but it is the part that scales worst. | Normalize-on-write, store unit vectors, and score with `vDSP_dotpr` over a contiguous buffer (mirror `EmbeddingIndex.search`). Keep the linear scan; just vectorize it. |
| F-2.3 | P1 | S | `Packages/GanchoKit/Sources/ClipboardCore/AdaptivePollingPolicy.swift`; `MacPasteboardMonitor.swift` | **Validated as sound.** Idle 1.5 s / active 250 ms, pause on lock, off-main content reads, in-flight coalescing (`pendingRead?.cancel()`), burst memory cap. This is the right capture design and meets the "<0.5% idle CPU" budget by construction. No change. | — |
| F-2.4 | P2 | M | `GRDBClipboardStore.search` (`:382-455`) regex path | Regex search fetches a full cursor and runs `NSRegularExpression` per row in Swift with no FTS pre-filter — O(N) over the whole table. Acceptable as an explicit "power user" mode, but at 100k rows it is the slowest query in the app. | Document the cost in the UI (regex = full scan), and optionally pre-narrow with the other filters (kind/date/source) before the scan — those already append to the WHERE clause, so a regex query with a date filter is cheap; make that the encouraged path. |
| F-2.5 | P2 | S | iOS keyboard: `Apps/GanchoKeyboard/KeyboardModel.swift:30-37`, `KeyboardClips.swift`, `BlobStore` thumbnails | **Validated.** The keyboard caps thumbnails FIFO at 24, decodes only the small cached thumbnail (never the full blob), and excludes sensitive clips. This directly addresses the "extension memory ceiling → crash" risk the prompt flags. No change; it's a model example. | — |

### Part 3 — Security & Vulnerabilities

| ID | Sev | Eff | Location | Finding & impact | Fix |
| --- | --- | --- | --- | --- | --- |
| F-3.1 | P1 | S | `Packages/GanchoKit/Package.swift:41-42` | The **encryption-critical** storage dependency is declared as `branch: "sqlcipher-7.11.0"` on a **personal fork** (`johnny4young/GRDB.swift`). A branch is a moving target: `swift package update`, a dropped `Package.resolved`, or a fresh checkout that re-resolves can silently pull a different commit into the layer that holds SQLCipher. `Package.resolved` currently pins `77e27af…`, which mitigates *reproducible* builds, but the manifest itself should not float. Supply-chain exposure is highest exactly here. | Pin the manifest to `revision: "77e27af…"` (or a signed tag). Document a process to rebase the fork onto upstream GRDB security releases and re-pin. Consider mirroring the fork under an org, not a personal account. |
| F-3.2 | P2 | M | `GRDBClipboardStore.exportJSON`/`exportCSV` (`:630-659`); `Apps/GanchoMac/SettingsView.swift:200`; `Apps/GanchoiOS/GanchoiOSApp.swift:779`; `gancho export` (`GanchoCLI.swift:159`) | Export includes **sensitive clips with full `contentText`** by default. `GanchoArchive.Options.excludeSensitive` defaults to `false` and **neither app nor the CLI passes it**. A secret the detector protected with a 10-minute expiry becomes permanent plaintext the moment the user exports. The threat model calls export "user-initiated" — true — but the current UX gives no choice and no warning. | Default the app export path to `excludeSensitive: true`, OR present a checkbox ("Include masked/sensitive items") defaulting to off, with a one-line disclosure. Add the same flag to `gancho export` (`--include-sensitive`, off by default). |
| F-3.3 | P2 | S | `GRDBClipboardStore.csvEscape` (`:661-666`) | CSV export is RFC-4180-correct but has **no formula-injection guard**. A clip whose text starts with `=`, `+`, `-`, or `@` is written verbatim; opened in Excel/Sheets it executes as a formula (data-exfil / command vector). Clipboard content is attacker-influenced by nature (you copy things from the web). | Prefix any field beginning with `= + - @ \t \r` with a `'` or a leading space before escaping (the standard OWASP CSV-injection mitigation). Keep JSON export byte-exact. |
| F-3.4 | P2 | M | `Packages/GanchoKit/Sources/GanchoKit/MCPAccess.swift` (`MCPServerConfig`), `GanchoCLI.swift:runEnable`, `MCPServer.swift` | The local MCP server has **no client authentication**. Enable state is a plain JSON file (`mcp-config.json`) in the store dir; any local process with filesystem access can flip `isEnabled: true, scope: all` and then read every non-sensitive clip via `gancho mcp`. Off-by-default and the sensitive veto both help, but "malicious local process" is exactly the threat the prompt names. | Require the *app* (not a bare file write) to grant/raise scope — e.g. store an app-written capability token the CLI must present, or surface a Privacy-Center prompt on first connection of a new client. At minimum, log + notify when scope is raised to `all`. |
| F-3.5 | P2 | M | `Packages/GanchoKit/Sources/GanchoAI/SensitiveDataDetector.swift:25-44` | Detector coverage gaps (false negatives). Present: cards (Luhn), AWS access/secret, Stripe `sk/rk`, GitHub `gh[pousr]_`, Slack `xox[baprs]-`, PEM, entropy-password. **Missing common secrets:** Google API keys (`AIza[0-9A-Za-z_-]{35}`), GCP service-account JSON, generic `Bearer <token>` / `Authorization:` headers, npm (`npm_…`), OpenAI (`sk-…` collides with Stripe prefix — worth disambiguating), Azure connection strings, and PGP private-key blocks (only `PRIVATE KEY` PEM is matched, not `-----BEGIN PGP PRIVATE KEY BLOCK-----`). | Add the high-value patterns above (each is one regex + a `Category`). Extend the 28-pattern test suite in lockstep. This is defense-in-depth; the `org.nspasteboard` veto is still the primary line. |
| F-3.6 | P1 | S | `KeychainPassphraseStore.swift`; `docs/ARCHITECTURE.md` "Encryption at rest" | **Validated as correct and honestly documented.** 256-bit random key, never derived from user input, `kSecAttrAccessibleAfterFirstUnlock` (most-protective level compatible with background capture + sync), `Failure` carries only `OSStatus`, idempotent first-launch race handling. The "never zero-knowledge — the Keychain holds the key" claim is accurate. No change. | — |
| F-3.7 | P2 | S | `ClipRecordMapper.swift:41-77` | **Validated.** Content-bearing fields (`title`, `preview`, `contentText`) ride `encryptedValues`; binary payloads ride `CKAsset`; only structural metadata (kind, hashes, timestamps, `boardIDs`) is plain. This matches invariant #5. One note: `sourceAppBundleID`/`sourceDeviceName` are plain fields — arguably low-sensitivity metadata, but a privacy-maximalist could argue device names are identifying. Consider moving `sourceDeviceName` to `encryptedValues`. | Optional: encrypt `sourceDeviceName`. |

### Part 4 — Reliability & Testing

| ID | Sev | Eff | Location | Finding & impact | Fix |
| --- | --- | --- | --- | --- | --- |
| F-4.1 | P2 | M | `GRDBClipboardStore.migrator` (`:192-374`) | 15 append-only migrations, GRDB-transactional per step (good). But there is **no forward-failure story beyond "reset the store"**: if migration `vN` throws mid-run on a user's DB, the encrypted-store path surfaces the "History isn't being saved" banner (per CHANGELOG 0.2.0) but there's no automated backup-before-migrate. Losing an encrypted store = losing history. | Before running pending migrations on the production path, snapshot the DB file (cheap file copy) and keep the last-known-good until the migration commits. Add a migration test that runs each version boundary against a seeded fixture. |
| F-4.2 | P2 | S | `RetentionEngine.swift:35-40` vs. board membership | The sensitive-lifetime purge clause excludes clips that are pinned, snippets, **or on any board** (`id NOT IN (SELECT clipID FROM clip_board)`). So a detected secret the user files into a board **never auto-expires** — contradicting the CHANGELOG promise that "detected secrets always follow the shorter Sensitive items limit." Likely intended (curated = exempt) but it's a silent exception to a stated guarantee. | Decide explicitly: either exempt board members (and soften the CHANGELOG wording), or keep sensitive expiry even for boarded clips (and document that boarding a secret won't preserve it). Add a test pinning the chosen behavior. |
| F-4.3 | P1 | S | Concurrency: capture + sync + retention | **Validated.** All three funnel through GRDB's single serialized `DatabaseWriter`, so simultaneous capture/purge/sync cannot race the DB. `@unchecked Sendable` uses are each justified (`UncheckedSendableBox` is read-only; `TelemetryPipeline` guards with `NSLock`; `DiagnosticLog` likewise). Swift 6 strict-concurrency posture holds. No change. | — |
| F-4.4 | P2 | M | Sync conflict path: `CKSyncEngineAdapter.handleFailedSave` (`:385-421`) + `SyncLocalStore.applyRemoteUpsert` | Last-writer-wins by `updatedAt` is implemented consistently (conflict → take server record, keep newer `updatedAt`). The **untested edge** is two devices editing the *same board membership* offline: membership rides the clip record (`boardIDs` plain field), so a concurrent add-on-A / remove-on-B resolves to whichever clip record wins by `updatedAt`, silently dropping the other device's membership change. | Add an on-hardware test (the prompt's own "verify on real hardware" gate). Consider membership as a set-merge rather than last-writer-wins, since add/remove are commutative-ish and users rarely intend a silent drop. |
| F-4.5 | P3 | S | `.github/workflows/ci.yml` coverage gate | Coverage floor is **70% lines**, enforced (not advisory) — good. It excludes `Tests` and `.build`. No branch-coverage gate; a floor this low can hide untested error paths in the crypto/sync code. | Raise gradually toward 80% and add a targeted higher floor for `GanchoKit`/`GanchoSync` specifically. |

### Part 5 — Privacy & App Store Compliance

| ID | Sev | Eff | Location | Finding & impact | Fix |
| --- | --- | --- | --- | --- | --- |
| F-5.1 | P1 | — | Cross-check of Section-2 invariants | **All seven invariants validated against code, not just docs:** veto-before-read (`MacPasteboardMonitor.pollOnce` checks `types` then vetoes before `scheduleRead`); no content logging (`NoContentLoggingTests` sweep over engine modules); on-device AI (`GanchoAI` imports only `FoundationModels`/`NaturalLanguage`, no `URLSession`); CloudKit isolation (only `GanchoSync` depends on it in `Package.swift`); Swift-6 concurrency; SQLCipher whole-DB encryption; bilingual gate. No violations found. | — |
| F-5.2 | P2 | S | All bundles have `PrivacyInfo.xcprivacy` (`GanchoMac/iOS/Share/Widgets/Keyboard`) | Present for every shipping bundle — good. `PrivacyManifestTests` exists. Not verifiable here whether the declared API-reason codes match actual API use (needs a build). | On a mac runner, cross-check declared reasons (UserDefaults, file-timestamp, disk-space APIs) against actual usage before submission. |
| F-5.3 | P2 | M | StoreKit vs. direct-download license (`License.swift`, `LicenseSigningKey`, `docs/RELEASING.md`) | The dual monetization path (StoreKit for App Store, Ed25519-signed Lemon Squeezy license for direct download) is cleanly gated by `LicenseSigningKey.isConfigured`. App Review risk: the paywall must not present iCloud sync as a shipped benefit until it is on real hardware — CHANGELOG 0.2.0 says this was fixed ("coming soon"). Keep that copy honest through launch. | Pre-submission: re-audit every paywall/entitlement string for "coming soon" accuracy; ensure background-pasteboard disclosure is macOS-only (it is). |

### Part 6 — Accessibility & Internationalization

| ID | Sev | Eff | Location | Finding & impact | Fix |
| --- | --- | --- | --- | --- | --- |
| F-6.1 | P2 | S | `Tests/…/LocalizationTests.swift:136-145` (hardcoded sweep regexes) | The bilingual gate is strong (per-bundle enforcement, plural handling, placeholder alignment). **But the hardcoded-prose sweep only matches `Text(`, `Label(`, `LocalizedStringResource`, Intent forms, and widget metadata.** It does **not** catch `Button("Save")`, `Toggle("…")`, `.navigationTitle("…")`, `Menu("…")`, `.alert("…")`, `.confirmationDialog("…")`, or `Section("…")` — all of which take a `LocalizedStringKey` and would ship untranslated prose silently. | Add these initializer/modifier patterns to the regex list. This closes the same class of loophole the suite's own comment describes catching for App Intents. |
| F-6.2 | P3 | S | `docs/ACCESSIBILITY.md`, VoiceOver announcements (CHANGELOG 0.3.2) | VoiceOver announcements, Dynamic Type, and reduce-transparency are documented and were recently expanded. Good posture. Cannot verify actual VoiceOver labels on the Liquid Glass panel without a running app. | On a mac runner, run the documented VoiceOver smoke (Privacy spec release-checklist item 5) and capture evidence. |

### Part 7 — General Recommendations

| ID | Sev | Eff | Location | Finding & impact | Fix |
| --- | --- | --- | --- | --- | --- |
| F-7.1 | P2 | S | `scripts/check-version-sync.sh:39-44` | `make release-check` reads plist versions with `/usr/libexec/PlistBuddy`, which exists **only on macOS**. On any Linux dev box or minimal CI image the command returns empty and the gate fails with a misleading `got ''`. This is a real portability defect (it made this audit's gate falsely "fail"). | Add a portable fallback (parse the `<string>` after each version key with `awk`/`grep`) when PlistBuddy is unavailable. **Fixed in this PR** (falls back cleanly; PlistBuddy still used when present). |
| F-7.2 | P3 | S | `docs/ARCHITECTURE.md` module graph vs. `Package.swift` | ARCHITECTURE lists all 7 engine-room targets accurately and matches the manifest — no drift here (contrast F-1.2, which is the *comment* in Package.swift). Doc is current. | No change; noted for completeness. |
| F-7.3 | P3 | S | `scripts/githooks`, `make hooks` | Pre-commit hook runs lint only. Onboarding is genuinely <10 min. Consider adding `make test` (or a fast subset) as a pre-push hook so the no-content-logging and localization gates run before code leaves the machine, not only in CI. | Add an opt-in pre-push hook. |
| F-7.4 | P3 | S | `Packages/GanchoKit/Package.resolved` | Lists `keyboardshortcuts` though the SwiftPM manifest doesn't depend on it (it's an app-level dep wired via `project.yml`). Harmless but can confuse `swift package` resolution audits. | Regenerate `Package.resolved` from the package alone, or document why the app-level pin lives here. |

---

## 4. Part 8 — World-Class Product Roadmap

Positioning against **Paste**, **Raycast Clipboard History**, **Maccy**, **CleanShot**, and
**Alfred**: Gancho's defensible wedge is **on-device AI + privacy-by-design + a real cross-Apple
sync story without operating servers**. Maccy is free but dumb; Paste is polished but cloud-synced
through its own infra; Raycast is developer-loved but macOS-only and account-centric; CleanShot is
capture-not-clipboard; Alfred is power-user but aging. None combine *private* semantic recall +
*on-device* transforms + *encrypted* Apple-native sync. That is the whole game.

### Next release (0.4.x — sharpen the wedge, close audit gaps)

1. **Ship the five fixes** in the shortlist below (§5). They are the price of a trustworthy public
   launch.
2. **"Ask your clipboard" as a headline feature, not a footnote.** It already exists
   (`ClipboardQAService`, grounded, sensitive-filtered, on-device). Give it a first-class surface
   (a search-bar mode, an App Intent, a Spotlight entry). *No competitor can ship this without a
   cloud round-trip.*
3. **Dev Actions breadth.** JWT/JSON/Base64/URL/color/UUID exist. Add: hash (md5/sha), timestamp
   ↔ human date, JSON↔YAML, URL-encode, case-convert, diff two clips. Expose each as an App Intent.
   This is the concrete "developers first" launch wedge the README names.
4. **Export safety UX** (F-3.2/F-3.3) — turn the privacy story into a visible feature ("sensitive
   items excluded by default").

### Next quarter (0.5–0.6 — platform leverage & trust)

5. **Deeper Shortcuts / App Intents + Spotlight.** Make every clip and every Dev Action addressable
   from Shortcuts and Spotlight. This is the Raycast/Alfred extensibility answer using Apple's own
   rails — lower maintenance, broader reach.
6. **`GanchoMCP` as the extension surface.** It already speaks MCP over the store boundary. Harden
   the auth (F-3.4), publish the tool schema, and market "bring your own AI agent, safely, on-device"
   — a differentiator Paste/CleanShot structurally cannot match.
7. **Trust, made visible.** Commission (and publish) a third-party security audit of the crypto/sync
   path; ship a public "what leaves your device: nothing" transparency page derived from the existing
   `docs/SECURITY-MODEL.md` (it's already written to be publishable). Launch to developers/power
   users first, where privacy is a purchase driver.
8. **On-hardware sync verification** (the README's own remaining item) + the F-4.4 membership-merge
   fix. Sync correctness is the one thing you cannot fake before charging for it.

### Long-term (post-PMF — expansion & platform)

9. **Portable data envelope before any non-Apple client.** `GanchoArchive` v1 is the seed. Formalize
   a versioned, documented capability matrix (per the ARCHITECTURE "Portability strategy") *before*
   committing engineering to Android/Windows/Linux. Keep it analysis-only until a product decision.
10. **visionOS spatial UI** only once usage justifies it (the plan already says iPad-compatible
    first). Don't build the spatial surface on spec.
11. **Monetization tuning.** Free tier (30-day/2,000-item, 15 pins/3 boards) is generous and correct
    as a distribution engine. Benchmark price against Paste (~$30/yr) and CleanShot (one-time ~$29):
    a one-time direct-download license + an optional sync subscription fits the local-first
    architecture better than forcing everyone into a subscription. A **team/enterprise tier** is
    feasible *without* servers via CloudKit sharing (`CKShare`) — the board zone is already isolated
    for exactly this (`BoardRecordMapper.zoneName`).
12. **Growth mechanics that respect privacy.** Snippet-library *sharing* (export a curated,
    sensitive-free board as a shareable `.ganchoarchive` or a signed link) is a viral loop that never
    touches history or secrets. Referrals via the license system. No social graph, no content
    harvesting — growth that is *on-brand* for a private tool.

**Developer platform (README's stated long-term intent).** Sequence: (a) freeze the `GanchoKit`
client contract (F-1.5), (b) publish `GanchoMCP` tool schemas + auth, (c) document the export
envelope, (d) open a plugin/extension registry once the MCP surface is authenticated. That order
turns "future non-Apple clients" from aspiration into a supported surface without destabilizing the
core.

---

## 5. If you only do five things

1. **Pin the GRDB/SQLCipher fork to a revision, not a branch** (F-3.1, P1/S). The encryption layer
   must not float on a moving branch of a personal fork.
2. **Make export sensitive-safe by default** (F-3.2, P2/M) + **guard CSV formula injection**
   (F-3.3, P2/S). Don't let a user-initiated export defeat the secret-detector's whole purpose.
3. **Authenticate the local MCP server** (F-3.4, P2/M). Any local process raising scope to `all`
   is the exact "malicious local process" threat in your own security model.
4. **Fix the two mechanical defects shipped in this PR** — the synchronous DB read on the semantic
   path (F-2.1) and the non-portable `release-check` gate (F-7.1) — and **widen the localization
   hardcoded-sweep** to `Button`/`Toggle`/`.navigationTitle`/`.alert` (F-6.1) so an untranslated
   label can't slip past the gate.
5. **Verify sync on real hardware and make membership a merge, not a silent last-writer-wins**
   (F-4.4, README's own remaining launch item). Sync is the one correctness bet you cannot defer
   past a paid launch.

---

## 6. What was changed in this PR (illustrative, minimal, Conventional Commits)

This audit's default is read-only. At the maintainer's explicit request ("implement all findings,
open a PR"), the **two smallest, provably-correct, build-safe** fixes were applied; everything else
remains a documented finding with a recommended fix, because this environment **cannot compile or
run the Swift test suite** and larger Swift changes must not ship unverified.

- `perf(search): await the semantic-search DB read so it can't block a concurrency thread` — F-2.1,
  a one-token change matching the sibling `await` read in the same function.
- `fix(release): fall back to a portable plist parser when PlistBuddy is absent` — F-7.1, verified
  to run on this Linux box (the version/CHANGELOG/formula checks now complete instead of
  false-failing).

Both are noted in the PR body as **requiring CI validation on `macos-26`** before merge, since they
could not be compiled here.
