// Verify Gancho's package-only and app-wide SwiftPM locks stay coherent.

import Darwin
import Foundation

private struct PinState: Decodable, Equatable {
    let branch: String?
    let checksum: String?
    let revision: String?
    let version: String?
}

private struct Pin: Decodable, Equatable {
    let identity: String
    let kind: String?
    let location: String?
    let state: PinState?
}

private struct LockDocument: Decodable {
    let pins: [Pin]
}

private struct LoadedLock {
    let pins: [String: Pin]
    let rawDocument: NSDictionary
}

private let expectedAppOnlyDependencies: Set<String> = ["keyboardshortcuts"]

private struct Arguments {
    var packageLock = "Packages/GanchoKit/Package.resolved"
    var appLock = "Dependencies/Package.resolved"
    var generatedLock =
        "Gancho.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
    var requireGenerated = false
    var runSelfTest = false

    static func parse() throws -> Self {
        var result = Self()
        var arguments = Array(CommandLine.arguments.dropFirst())
        while !arguments.isEmpty {
            let argument = arguments.removeFirst()
            switch argument {
            case "--package-lock":
                result.packageLock = try value(after: argument, from: &arguments)
            case "--app-lock":
                result.appLock = try value(after: argument, from: &arguments)
            case "--generated-lock":
                result.generatedLock = try value(after: argument, from: &arguments)
            case "--require-generated":
                result.requireGenerated = true
            case "--self-test":
                result.runSelfTest = true
            default:
                throw ValidationError("unknown argument: \(argument)")
            }
        }
        return result
    }

    private static func value(
        after option: String, from arguments: inout [String]
    ) throws
        -> String
    {
        guard !arguments.isEmpty else {
            throw ValidationError("missing value after \(option)")
        }
        return arguments.removeFirst()
    }
}

private struct ValidationError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

private func loadLock(at path: String) throws -> LoadedLock {
    let url = URL(fileURLWithPath: path)
    let data: Data
    do {
        data = try Data(contentsOf: url)
    } catch {
        throw ValidationError("missing dependency lock: \(path)")
    }

    let document: LockDocument
    let rawDocument: NSDictionary
    do {
        document = try JSONDecoder().decode(LockDocument.self, from: data)
        guard let dictionary = try JSONSerialization.jsonObject(with: data) as? NSDictionary else {
            throw ValidationError("dependency lock is not a JSON object: \(path)")
        }
        rawDocument = dictionary
    } catch let error as ValidationError {
        throw error
    } catch {
        throw ValidationError("invalid dependency lock \(path): \(error)")
    }

    var pins: [String: Pin] = [:]
    for pin in document.pins {
        guard pins.updateValue(pin, forKey: pin.identity) == nil else {
            throw ValidationError("dependency lock repeats \(pin.identity): \(path)")
        }
    }
    return LoadedLock(pins: pins, rawDocument: rawDocument)
}

private func validate(_ arguments: Arguments) throws -> (packageCount: Int, appCount: Int) {
    let package = try loadLock(at: arguments.packageLock)
    let app = try loadLock(at: arguments.appLock)

    guard package.pins["keyboardshortcuts"] == nil else {
        throw ValidationError(
            "the package-only lock must not contain project dependency keyboardshortcuts")
    }
    guard app.pins["keyboardshortcuts"] != nil else {
        throw ValidationError(
            "the app-wide lock must contain project dependency keyboardshortcuts")
    }

    let appOnlyDependencies = Set(app.pins.keys).subtracting(package.pins.keys)
    guard appOnlyDependencies == expectedAppOnlyDependencies else {
        let actual = appOnlyDependencies.sorted().joined(separator: ", ")
        throw ValidationError(
            "app-wide lock has an invalid project-only dependency set: "
                + "expected keyboardshortcuts, found \(actual.isEmpty ? "none" : actual)")
    }

    for identity in package.pins.keys.sorted() {
        guard let packagePin = package.pins[identity], let appPin = app.pins[identity] else {
            throw ValidationError("app-wide lock is missing package dependency \(identity)")
        }
        guard packagePin == appPin else {
            throw ValidationError(
                "dependency \(identity) resolves differently in package and app locks")
        }
    }

    if arguments.requireGenerated {
        guard FileManager.default.fileExists(atPath: arguments.generatedLock) else {
            throw ValidationError(
                "generated Xcode workspace lock is missing: \(arguments.generatedLock)")
        }
        let generated = try loadLock(at: arguments.generatedLock)
        guard generated.rawDocument.isEqual(app.rawDocument) else {
            throw ValidationError(
                "generated Xcode workspace lock differs from Dependencies/Package.resolved; "
                    + "run make project to restore it or make resolve-dependencies after an "
                    + "intentional requirement change")
        }
    }

    return (package.pins.count, app.pins.count)
}

private func runPolicySelfTest() throws {
    let fileManager = FileManager.default
    let temporaryDirectory = fileManager.temporaryDirectory
        .appendingPathComponent("dependency-check-\(UUID().uuidString)")
    try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    defer { try? fileManager.removeItem(at: temporaryDirectory) }

    let packageLock = temporaryDirectory.appendingPathComponent("package.json")
    let appLock = temporaryDirectory.appendingPathComponent("app.json")

    func writeLock(_ identities: [String], to url: URL) throws {
        let pins = identities.map { identity in
            [
                "identity": identity,
                "kind": "remoteSourceControl",
                "location": "https://example.com/\(identity).git",
                "state": [
                    "revision": "revision-\(identity)",
                    "version": "1.0.0"
                ]
            ] as [String: Any]
        }
        let data = try JSONSerialization.data(
            withJSONObject: ["pins": pins, "version": 3],
            options: [.prettyPrinted, .sortedKeys])
        try data.write(to: url)
    }

    var arguments = Arguments()
    arguments.packageLock = packageLock.path
    arguments.appLock = appLock.path

    try writeLock(["shared"], to: packageLock)
    try writeLock(["shared", "keyboardshortcuts"], to: appLock)
    _ = try validate(arguments)

    try writeLock(["shared", "keyboardshortcuts", "unexpected"], to: appLock)
    do {
        _ = try validate(arguments)
        throw ValidationError("self-test accepted an unexpected app-only dependency")
    } catch let error as ValidationError {
        guard error.description.contains("found keyboardshortcuts, unexpected") else {
            throw ValidationError("self-test failed for the wrong reason: \(error)")
        }
    }

    print("✓ dependency lock policy self-test passed")
}

do {
    let arguments = try Arguments.parse()
    if arguments.runSelfTest {
        try runPolicySelfTest()
    }
    let counts = try validate(arguments)
    print(
        "✓ dependency locks agree (\(counts.packageCount) package pins, \(counts.appCount) app pins)"
    )
} catch {
    FileHandle.standardError.write(Data("✗ \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
