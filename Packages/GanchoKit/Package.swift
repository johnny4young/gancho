// swift-tools-version: 6.2
// GanchoKit — the engine room. All feature/core code lives here; the app
// targets in Apps/ are thin shells. Four library products:
//   GanchoKit      — models, store protocols, sync boundary
//   ClipboardCore  — platform pasteboard adapters (macOS capture, iOS intent-based)
//   GanchoAI       — on-device intelligence (tier-0 classifier today)
//   GanchoDesign   — design tokens shared across platforms

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
    ],
    dependencies: [
        // Storage engine (SQLite). Decision and rationale: docs/ARCHITECTURE.md.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "GanchoKit", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "ClipboardCore", dependencies: ["GanchoKit"]),
        .target(name: "GanchoAI", dependencies: ["GanchoKit"]),
        .target(name: "GanchoDesign"),
        .testTarget(name: "GanchoKitTests", dependencies: ["GanchoKit"]),
        .testTarget(name: "ClipboardCoreTests", dependencies: ["ClipboardCore"]),
        .testTarget(name: "GanchoAITests", dependencies: ["GanchoAI"]),
    ]
)
