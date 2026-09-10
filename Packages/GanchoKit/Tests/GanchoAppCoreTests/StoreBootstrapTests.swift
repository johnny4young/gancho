import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// The store-open decision, which used to be two inlined trees nothing could
/// reach: it ran once, inside an app initializer, behind launch arguments.
@Suite("StoreBootstrap — the launch decision, finally reachable")
struct StoreBootstrapTests {
    private func configuration(
        encryptedThrowaway: Bool = false,
        productionDirectory: URL? = nil
    ) -> StoreBootstrap.Configuration {
        let resolved =
            productionDirectory
            ?? FileManager.default.temporaryDirectory
            .appendingPathComponent("bootstrap-prod-\(UUID().uuidString)")
        return StoreBootstrap.Configuration(
            productionDirectory: { resolved },
            throwawayIsEncrypted: encryptedThrowaway,
            throwawayDirectoryPrefix: "bootstrap-test-store")
    }

    @Test("A plain launch asks for the user's real store")
    func plainLaunchIsProduction() {
        #expect(StoreBootstrap.request(arguments: []) == .production)
        #expect(StoreBootstrap.request(arguments: ["gancho", "-other-flag"]) == .production)
    }

    @Test("Each hook is recognized on its own")
    func eachHookIsRecognized() {
        #expect(StoreBootstrap.request(arguments: ["-use-temp-durable-store"]) == .throwaway)
        #expect(StoreBootstrap.request(arguments: ["-force-ephemeral-store"]) == .ephemeral)
    }

    @Test("Throwaway wins over ephemeral, in either argument order")
    func throwawayOutranksEphemeral() {
        // The one combination the two shells disagreed on before this existed:
        // macOS checked throwaway first, iOS checked ephemeral first. Nothing
        // passes both, so the disagreement was unreachable — and unreadable
        // without opening both initializers. Asserted in both orders so the
        // rule is precedence, not argument position.
        #expect(
            StoreBootstrap.request(
                arguments: ["-use-temp-durable-store", "-force-ephemeral-store"]) == .throwaway)
        #expect(
            StoreBootstrap.request(
                arguments: ["-force-ephemeral-store", "-use-temp-durable-store"]) == .throwaway)
    }

    @Test("Ephemeral opens nothing and touches no directory")
    func ephemeralOpensNothing() {
        let opened = StoreBootstrap.open(.ephemeral, configuration: configuration())
        #expect(opened.durable == nil)
        #expect(opened.directory == nil, "there is no location to report when nothing was opened")
    }

    @Test("A throwaway store is durable, fresh, and under its own prefix")
    func throwawayIsDurableAndUnique() throws {
        let first = StoreBootstrap.open(.throwaway, configuration: configuration())
        let second = StoreBootstrap.open(.throwaway, configuration: configuration())

        let firstDirectory = try #require(first.directory)
        let secondDirectory = try #require(second.directory)
        #expect(first.durable != nil, "the point of the throwaway store is that it is real")
        #expect(
            firstDirectory != secondDirectory,
            "two launches must not share a store, or one test seeds another")
        #expect(firstDirectory.lastPathComponent.hasPrefix("bootstrap-test-store-"))
        #expect(
            FileManager.default.fileExists(atPath: firstDirectory.path),
            "the directory must exist before the store opens into it")

        try? FileManager.default.removeItem(at: firstDirectory)
        try? FileManager.default.removeItem(at: secondDirectory)
    }

    @Test("The location is reported even when the store could not be opened")
    func locationSurvivesAFailedOpen() {
        // A FAILING opener, injected. Two reasons this is not just convenience:
        // the real production opener reads and CREATES the user's database key
        // through `KeychainPassphraseStore`, which no unit test may touch; and
        // without injection the failure branch is unreachable except by
        // breaking someone's actual store.
        //
        // What must hold: the location is reported REGARDLESS of success,
        // because macOS anchors its MCP config directory to it. Anchoring that
        // to success would move the config file on exactly the launches where
        // the store failed to open.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bootstrap-prod-\(UUID().uuidString)")
        let spy = OpenerSpy()
        let opened = StoreBootstrap.open(
            .production,
            configuration: configuration(productionDirectory: directory),
            opener: spy.opener(returning: nil))

        #expect(opened.durable == nil, "the opener failed, so there is no store")
        #expect(opened.directory == directory, "the location is still where it tried")
        try? FileManager.default.removeItem(at: directory)
    }

    @Test("Each request hands the opener the parameters its shell configured")
    func openerReceivesTheConfiguredParameters() throws {
        // The per-shell mapping nothing else pins: macOS encrypts its throwaway
        // store and shares no Keychain group, iOS does the opposite. Asserting
        // the CALL rather than the result is the only way to see it, since both
        // shells end up with "some store" either way.
        let macOS = configuration(encryptedThrowaway: true)
        let iOS = StoreBootstrap.Configuration(
            productionDirectory: { URL(fileURLWithPath: "/tmp/ios-prod") },
            keychainAccessGroup: "group.example.keys",
            throwawayIsEncrypted: false,
            throwawayDirectoryPrefix: "ios-throwaway")

        let macThrowaway = OpenerSpy()
        _ = StoreBootstrap.open(
            .throwaway, configuration: macOS, opener: macThrowaway.opener())
        let macCall = try #require(macThrowaway.calls.first)
        #expect(macCall.encrypted, "the Mac throwaway store exercises the real open path")
        #expect(
            macCall.keychainAccessGroup == nil,
            "a per-launch disposable store shares no group")

        let iosThrowaway = OpenerSpy()
        _ = StoreBootstrap.open(
            .throwaway, configuration: iOS, opener: iosThrowaway.opener())
        let iosCall = try #require(iosThrowaway.calls.first)
        #expect(
            !iosCall.encrypted,
            "encrypting here would send a simulator run at the App Group Keychain")

        let iosProduction = OpenerSpy()
        _ = StoreBootstrap.open(
            .production, configuration: iOS, opener: iosProduction.opener())
        let productionCall = try #require(iosProduction.calls.first)
        #expect(productionCall.encrypted, "the user's real store is always encrypted")
        #expect(
            productionCall.keychainAccessGroup == "group.example.keys",
            "iOS shares the passphrase with its extensions")
    }

    @Test("An ephemeral launch never asks the opener for anything")
    func ephemeralNeverCallsTheOpener() {
        let spy = OpenerSpy()
        _ = StoreBootstrap.open(.ephemeral, configuration: configuration(), opener: spy.opener())
        #expect(spy.calls.isEmpty, "there is nothing to open, so nothing may be attempted")
    }
}

/// Records what the opener was handed, so a test can assert on the CALL and not
/// only on what came back.
///
/// `@unchecked Sendable` over a lock because ``StoreBootstrap/Opener`` is
/// `@Sendable`: the closure has to capture something these synchronous
/// assertions can read back afterwards.
private final class OpenerSpy: @unchecked Sendable {
    struct Call {
        let directory: URL
        let encrypted: Bool
        let keychainAccessGroup: String?
    }

    private let lock = NSLock()
    private var storage: [Call] = []

    var calls: [Call] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func opener(returning store: GRDBClipboardStore? = nil) -> StoreBootstrap.Opener {
        { [self] directory, encrypted, keychainAccessGroup in
            lock.lock()
            storage.append(
                Call(
                    directory: directory, encrypted: encrypted,
                    keychainAccessGroup: keychainAccessGroup))
            lock.unlock()
            return store
        }
    }
}
