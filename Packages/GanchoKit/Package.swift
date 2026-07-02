// swift-tools-version: 6.2
// GanchoKit — the engine room. All feature/core code lives here; the app
// targets in Apps/ are thin shells. Eight library products plus a CLI:
//   GanchoKit      — models, store protocols, sync boundary
//   ClipboardCore  — platform pasteboard adapters (macOS capture, iOS intent-based)
//   GanchoAI       — on-device intelligence (tier-0 classifier today)
//   GanchoDesign   — design tokens shared across platforms
//   GanchoTelemetry — bucket-only analytics transport (kept outside the core)
//   GanchoSync     — CloudKit sync adapter (the only CloudKit importer)
//   GanchoAppCore  — platform-neutral app-layer coordinators shared by both shells
//   GanchoMCP      — local MCP server protocol + tools
//   gancho         — executable: the CLI + stdio MCP server (Homebrew)

import PackageDescription

let package = Package(
    name: "GanchoKit",
    platforms: [
        .macOS(.v26),
        .iOS(.v26),
    ],
    products: [
        .library(name: "GanchoKit", targets: ["GanchoKit"]),
        .library(name: "ClipboardCore", targets: ["ClipboardCore"]),
        .library(name: "GanchoAI", targets: ["GanchoAI"]),
        .library(name: "GanchoDesign", targets: ["GanchoDesign"]),
        // Telemetry transport, deliberately OUTSIDE the engine room so the
        // core never links a network SDK (threat-model boundary).
        .library(name: "GanchoTelemetry", targets: ["GanchoTelemetry"]),
        // CloudKit sync adapter — the ONLY target allowed to import
        // CloudKit; the core stays behind the `SyncEngine` boundary.
        .library(name: "GanchoSync", targets: ["GanchoSync"]),
        // Platform-neutral app-layer coordinators shared by the Mac and iOS
        // shells. May be @MainActor; must NOT import AppKit/UIKit/SwiftUI/CloudKit.
        .library(name: "GanchoAppCore", targets: ["GanchoAppCore"]),
        // Local MCP server protocol + tools. Pure logic over the store
        // boundary; the `gancho` executable wires it to stdio. The apps do
        // NOT link it — they only need the model types in GanchoKit.
        .library(name: "GanchoMCP", targets: ["GanchoMCP"]),
        // The `gancho` CLI + stdio MCP server, distributed via Homebrew.
        .executable(name: "gancho", targets: ["gancho"]),
    ],
    dependencies: [
        // Storage engine (SQLite) — SQLCipher-enabled fork for whole-database
        // encryption. Upstream GRDB can't turn on SQLCipher without a fork
        // (package traits need Xcode-UI support it still lacks); the fork only
        // uncomments the marked `// GRDB+SQLCipher:` lines on the v7.11.0 tag,
        // pulling Zetetic's official SQLCipher.swift. Rationale: docs/ARCHITECTURE.md.
        // Pinned to an exact revision (not the moving `sqlcipher-7.11.0` branch)
        // so the encryption layer can never silently change under a re-resolve.
        // When rebasing the fork onto an upstream GRDB/SQLCipher security
        // release, update this revision hash deliberately in the same commit.
        .package(
            url: "https://github.com/johnny4young/GRDB.swift.git",
            revision: "77e27afdf29bc298a14d2b19e2bb5bcf466df632"),
        // Layout-aware keycodes for the synthetic ⌘V (covers Dvorak-QWERTY⌘).
        // Inherited practice from years of Maccy/community plumbing (MIT).
        .package(url: "https://github.com/Clipy/Sauce.git", from: "2.4.0"),
        // Privacy-first product analytics (bucket-only events). Confined to
        // the GanchoTelemetry target.
        .package(url: "https://github.com/TelemetryDeck/SwiftSDK", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "GanchoKit",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")],
            // SQLCipher APIs (`usePassphrase`) are gated behind this flag in
            // both GRDB and our own `#if SQLITE_HAS_CODEC` encryption path.
            swiftSettings: [.define("SQLITE_HAS_CODEC")]),
        .target(
            name: "ClipboardCore",
            dependencies: [
                "GanchoKit",
                .product(name: "Sauce", package: "Sauce", condition: .when(platforms: [.macOS])),
            ]),
        .target(name: "GanchoAI", dependencies: ["GanchoKit"]),
        .target(name: "GanchoDesign", dependencies: ["GanchoKit"]),
        .target(
            name: "GanchoTelemetry",
            dependencies: [
                "GanchoKit",
                .product(name: "TelemetryDeck", package: "SwiftSDK"),
            ]),
        .target(name: "GanchoSync", dependencies: ["GanchoKit"]),
        .target(name: "GanchoAppCore", dependencies: ["GanchoKit", "GanchoAI", "GanchoSync"]),
        .target(name: "GanchoMCP", dependencies: ["GanchoKit"]),
        .executableTarget(name: "gancho", dependencies: ["GanchoKit", "GanchoMCP"]),
        .testTarget(
            name: "GanchoKitTests",
            dependencies: ["GanchoKit"],
            // Lets the on-disk encryption tests compile their `#if SQLITE_HAS_CODEC` path.
            swiftSettings: [.define("SQLITE_HAS_CODEC")]),
        .testTarget(name: "GanchoMCPTests", dependencies: ["GanchoMCP", "GanchoKit"]),
        .testTarget(name: "GanchoSyncTests", dependencies: ["GanchoSync", "GanchoKit"]),
        .testTarget(name: "GanchoAppCoreTests", dependencies: ["GanchoAppCore"]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"]),
        .testTarget(name: "GanchoAITests", dependencies: ["GanchoAI"]),
        .testTarget(name: "GanchoDesignTests", dependencies: ["GanchoDesign"]),
    ]
)
