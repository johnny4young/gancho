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
        // Production encrypts, which needs a Keychain this test process may not
        // have. Either outcome is fine here — what must hold is that the
        // location is reported REGARDLESS, because macOS anchors its MCP config
        // directory to it. Anchoring that to success would move the config file
        // on exactly the launches where the store failed to open.
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("bootstrap-prod-\(UUID().uuidString)")
        let opened = StoreBootstrap.open(
            .production, configuration: configuration(productionDirectory: directory))

        #expect(opened.directory == directory)
        try? FileManager.default.removeItem(at: directory)
    }
}
