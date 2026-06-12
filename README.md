# Gancho — Smart Clipboard

> Your clipboard, everywhere — private by design. Clipboard history + a curated
> snippet library for Mac, iPhone, and iPad, with on-device intelligence.
> *Gancho* means “hook” in Spanish: it’s where you hang everything you copy.
> And when something *tiene gancho*, it hooks you.

**Status: pre-alpha scaffold.**

## The two worlds

- **History** — ephemeral, captured automatically on macOS (intent-based on iOS).
- **Library** — permanent and curated: snippets, templates, pins.

The bridge is the signature gesture: *promote* any clip into the Library with
one shortcut.

## Setup (< 10 min)

Prerequisites: macOS 26+, Xcode 26+, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/johnny4young/gancho.git
cd gancho
make test    # package unit tests (Swift Testing)
make open    # generate Gancho.xcodeproj and open Xcode
```

| Target | What it does |
| --- | --- |
| `make project` | Regenerate `Gancho.xcodeproj` from `project.yml` |
| `make build` / `make build-ios` | Build the macOS / iOS app (unsigned Debug) |
| `make test` | Run package unit tests |
| `make format` / `make lint` | Format / verify Swift sources |
| `make clean` | Remove generated project + build artifacts |

## Layout

```
Apps/GanchoMac        Thin macOS shell (menu bar, pre-alpha)
Apps/GanchoiOS        Thin iOS shell (pre-alpha)
Packages/GanchoKit    The engine room (SwiftPM):
  GanchoKit             models, store protocols, SyncEngine boundary
  ClipboardCore         pasteboard adapters (macOS polling / iOS intent-based)
  GanchoAI              on-device intelligence (tier-0 classifier)
  GanchoDesign          design tokens
docs/ARCHITECTURE.md  Decisions and layering
```

## Key decisions (see docs/ARCHITECTURE.md)

- Swift 6 strict concurrency from commit 1; app modules default to `@MainActor`.
- Minimum macOS 26 / iOS 26; SDK-27 APIs adopted behind `#available`.
- Storage: GRDB (SQLite) + FTS5; sync: CKSyncEngine with encrypted fields —
  never raw SwiftData+CloudKit. Validated by dedicated spikes before any
  schema is promoted.
- Privacy is a feature: sensitive pasteboard types are never stored; no
  clipboard content ever leaves the device to our servers (we have none).

## License

Proprietary. © 2026 Johnny Young. All rights reserved.
