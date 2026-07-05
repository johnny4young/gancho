# Gancho — Handoff para continuar local (con Xcode)

**Fecha:** 2026-07-03 · **Autor:** sesión de ingeniería Claude Code
**Estado:** todo lo verde ya está en `main`; queda 1 commit de tests en la rama y una cola de refactor documentada.

---

## 0. TL;DR

- `main` (`752927e`) ya tiene **toda** la campaña: auditoría + fixes + features (#23) y el refactor estructural (#24).
- La rama `claude/gancho-engineering-audit-byfy24` (`197078f`) está **1 commit por delante** de `main`: UI tests + hook de seed. **CI verde. Sin PR.**
- Lo que falta hacer **local (con Xcode)**: correr los UI tests, un smoke test de ~10 min, cerrar 2 `TODO(local)`, y (opcional) retomar la cola de refactor `.audit/09` (PR-G/H/I.2/L).

---

## 1. Git — dónde está cada cosa

```
main            752927e   #24 merge (refactor) — incluye #23 (audit) por debajo
  └─ rama       197078f   test(ui): XCUITest + seed hook  ← 1 commit encima de main, CI verde, sin PR
```

Traer la rama a tu Mac:

```bash
git fetch origin
git checkout claude/gancho-engineering-audit-byfy24   # 197078f
# o para revisar el diff del commit de tests:
git diff main...claude/gancho-engineering-audit-byfy24   # 5 archivos, +235/-2
```

Fusionar el commit de tests a `main` cuando lo valides (elegí uno):
```bash
# Opción PR (recomendado para dejar rastro/CI):
#   abrí un PR de la rama → main en GitHub y merge.
# Opción local:
git checkout main && git merge --no-ff claude/gancho-engineering-audit-byfy24 && git push origin main
```

> Nota: el entorno donde se hizo esto **no tenía toolchain de Swift** (Linux), por eso CI (`macos-26`) fue la compuerta de compilación/test. En tu Mac tenés compilación en segundos — eso desbloquea todo lo que quedó pendiente.

---

## 2. Correr los tests (en tu Mac)

```bash
make project        # regenera Gancho.xcodeproj desde project.yml (xcodegen)
make test           # unit tests del paquete (Swift Testing) — lo que CI ya corre
make build          # build macOS (Debug, unsigned)
make build-ios      # build iOS (generic device)
make lint           # swift-format --strict (no cambia archivos)

# UI tests (XCUITest) — CI NO los corre; son locales, runner firmado:
make test-ui        # macOS  → Tests/GanchoUITests/*
make test-ui-ios    # iOS sim → Tests/GanchoiOSUITests/*
#   override sim: make test-ui-ios IOS_SIM_DEST='platform=iOS Simulator,name=iPhone 17'
#   firma:        make test-ui TEST_UI_SIGNING_FLAGS="DEVELOPMENT_TEAM=XXXXXXXXXX"
```

---

## 3. Smoke test manual (~10 min) — valida lo que CI no ve

El refactor #24 es *behavior-preserving*, pero CI no ejercita la app real. Tocá estos 5 flujos (mapeados a lo que se refactorizó):

1. **Captura → enriquecido:** copiá algo → aparece en la historia y le llega título. *(EnrichmentService / ClipItemFactory)*
2. **Deshacer borrado:** en el panel macOS, borrá un clip → toast **"Deshacer"** → tap → vuelve en su lugar. *(DeletionCoordinator)*
3. **Boards + paywall:** creá/borrá un board; en free, al pasar el límite (3) → **paywall**. *(BoardsController)*
4. **Sync toggle** (si tenés iCloud/Pro): activar/desactivar → el indicador de estado cambia. *(SyncController)*
5. **Paste + export:** pegá un clip (⌘V) y exportá historial (Settings → Export). *(paste / ClipExporter)*

Si algo falla ahí, es puntual — el núcleo de cada controlador tiene unit tests en `GanchoAppCoreTests`.

---

## 4. Los 2 `TODO(local)` a cerrar en Xcode

Los UI tests nuevos son un scaffold correcto por patrón, pero dos puntos no se pudieron pinear sin simulador real:

### 4.1 `Tests/GanchoUITests/RefactorFlowUITests.swift:123` — umbral del paywall
- Hoy el test verifica solo la afordance "New board" + el prompt.
- **Problema:** bajo `-force-ephemeral-store`, `AppModel.createBoard` hace `guard let grdbStore` y el store efímero deja `grdbStore == nil` → crear board es no-op. No se puede llegar al paywall end-to-end sin un store durable descartable.
- **Cómo cerrarlo:** agregar un hook de *store durable temporal* para tests (p. ej. `-use-temp-durable-store` que abra un `GRDBClipboardStore.encrypted` en un directorio temporal borrado al salir), sembrar/crear 3 boards y assert que aparece `paywall`. Recordá que el paywall además exige `first-pasteback-at` seteado (por eso el test pasa `-first-pasteback-at 1`, que NSArgumentDomain vuelca a UserDefaults).

### 4.2 `Tests/GanchoiOSUITests/CaptureFlowUITests.swift:54` — tap del UIPasteControl
- Hoy `testPasteControlIsPresent` asserta que existe `paste-control`; `testSeededCaptureAppearsInHistory` usa el seed.
- **Cómo cerrarlo:** en simulador real, poné texto en `UIPasteboard.general`, tap del `UIPasteControl`, y assert la nota `save-note` ("Saved"). El UIPasteControl no se puede disparar headless.

---

## 5. Hooks de test disponibles (launch args)

Ya existen y son deterministas (guardados, no afectan runs normales):
- `-open-panel-on-launch` (macOS) — abre el panel.
- `-open-privacy-center-on-launch` — ruta directa al Privacy Center.
- `-force-ephemeral-store` — store en memoria (no toca el store real).
- `-use-in-process-status-item` (macOS) — status item testeable.
- **`-seed-sample-clips`** (NUEVO, macOS+iOS) — siembra 3 clips sintéticos ("seed alpha", "https://seed.example/one", "seed beta") por el pipeline real. **Solo actúa junto con `-force-ephemeral-store`** (guarda doble: arg + store efímero).

`accessibilityIdentifier` útiles: `search-field`, `clip-row`, `toast-undo` (NUEVO, solo el Undo de borrado), `board-new`, `paywall`, `privacy-center` / `ios-privacy-center`, `copy-diagnostics`, `save-note`, `paste-control`, `filter-links`, `capture-notice`.

---

## 6. Cola de refactor pendiente (`.audit/09-architecture-refactor-plan.md`)

Lo que quedó **fuera** de #24 — **hacelo con Xcode local** (fallos que CI no detecta: observación SwiftUI, índices de render, visibilidad):

| Ítem | Qué | Por qué necesita compilador local |
|---|---|---|
| **PR-G (resto)** | `HistoryListViewModel` / `CaptureIngestor` (iOS): descomponer `IOSAppModel` en view-models | Re-apunta la observación de `@Observable` en muchas vistas; un forward roto **compila y pasa CI** pero rompe la reactividad → regresión silenciosa. |
| **PR-H (resto)** | Coordinadores mac: `CaptureIngestPipeline`, `PasteCoordinator`, `WindowRegistry`, etc. | `PasteCoordinator` toca AppKit directo (`NSWorkspace`, `panel.hide`) → extracción fragmentada; `WindowRegistry` es rename ancho por 8 vistas. |
| **PR-I.2** | Fusionar el *grouping walk* de `PanelView` sobre `ClipSections.grouped` (el tipo `ClipSection` ya convergió) | El mapeo de índice global (para nav de teclado / `selectedIndex` / `loadMore`) es lógica de render que CI no observa. |
| **PR-L** | Congelar el contrato: `public`→`internal`/`@_spi` en `GRDBClipboardStore` + extensiones | Delicado pero **CI SÍ lo valida** (si rompés el CLI/tests, falla el build). Candidato razonable para hacer con iteración rápida local. |

**Recomendación:** cuando quieras retomarlas, yo escribo los diffs y vos compilás/verificás en Xcode al instante (mucho mejor risk/reward que ciclos de CI a ciegas). Empezá por **PR-I.2** (bajo, ya está el tipo compartido) o **PR-L** (CI de red).

Patrón que usó #24 y conviene mantener: extraer a `GanchoAppCore` (target neutro, sin AppKit/UIKit/SwiftUI/CloudKit), **mantener el estado `@Observable` en el app model** y pasar callbacks (así no cambian las vistas), y **parametrizar** las divergencias entre las dos apps en vez de unificarlas.

---

## 7. Release (cuando estés conforme)

Último tag: **v0.3.2** (#22). Todo #23/#24 está en `main` **sin liberar**.

```bash
# 1) bump de versión + changelog:
#    project.yml: MARKETING_VERSION 0.3.2 → 0.3.3 ; CURRENT_PROJECT_VERSION 5 → 6
#    CHANGELOG.md: nueva sección [0.3.3]
#    scripts/homebrew/gancho.rb: version → 0.3.3
make release-check      # verifica que project.yml/CHANGELOG/formula/Info.plist concuerden
# 2) merge del bump a main, luego:
git tag v0.3.3 && git push origin v0.3.3   # dispara release.yml (DMG firmado+notarizado, appcast, Homebrew) — owner-only
```

Ojo: la auditoría cerró features grandes (rekey raw-key **sin cablear** por diseño — ver `.audit/06 §5`); si vas a liberar, revisá los "Not wired / follow-ups" de la descripción de #23.

---

## 8. Referencias rápidas

- Plan de refactor completo: `.audit/09-architecture-refactor-plan.md`
- Todos los dossiers de auditoría: `.audit/02..24`
- `GanchoAppCore` (lo nuevo compartido): `Packages/GanchoKit/Sources/GanchoAppCore/` + tests en `Packages/GanchoKit/Tests/GanchoAppCoreTests/`
- Contrato de cliente (facets): `Packages/GanchoKit/Sources/GanchoKit/ClientContract.swift`
- CI: `.github/workflows/ci.yml` (macos-26; `xcodebuild build`, **no** corre UI tests)
- Reglas del repo: `AGENTS.md` (≤100 cols, swift-format, engines sin logging, Conventional Commits, sin trailers de co-autoría IA)
