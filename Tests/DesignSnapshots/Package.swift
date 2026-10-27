// swift-tools-version: 6.1
import PackageDescription

// Compares the PNGs `GanchoUITests/DesignV4SnapshotUITests` captures against
// baselines. Separate from the app graph: UI test bundles cannot load Swift
// Testing, which swift-snapshot-testing imports. Run through `make test-snapshots`.
let package = Package(
    name: "DesignSnapshots",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/pointfreeco/swift-snapshot-testing", exact: "1.19.7")
    ],
    targets: [
        .testTarget(
            name: "DesignSnapshotTests",
            dependencies: [.product(name: "SnapshotTesting", package: "swift-snapshot-testing")]
        )
    ]
)
