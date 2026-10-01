import Foundation
import Testing

@testable import GanchoAppCore

@Suite("DeviceProvenance — capture provenance name")
struct DeviceProvenanceTests {
    @Test("Normalization trims and collapses unusable names to nil")
    func normalization() {
        #expect(DeviceProvenance.normalized("Fixture Mac") == "Fixture Mac")
        #expect(DeviceProvenance.normalized("  Fixture Mac \n") == "Fixture Mac")
        #expect(DeviceProvenance.normalized("") == nil, "blank must stay NULL, not ''")
        #expect(DeviceProvenance.normalized("   \n ") == nil)
        #expect(DeviceProvenance.normalized(nil) == nil)
    }

    @Test("The supplied provider is read once and is not cached")
    @MainActor
    func readsOnlyTheInjectedProvider() {
        var reads = 0
        var raw: String? = "  Fixture Mac \n"
        let provider = {
            reads += 1
            return raw
        }
        #expect(DeviceProvenance.currentDeviceName(using: provider) == "Fixture Mac")
        #expect(reads == 1)
        raw = " Fixture iPhone "
        #expect(DeviceProvenance.currentDeviceName(using: provider) == "Fixture iPhone")
        #expect(reads == 2)
        raw = nil
        #expect(DeviceProvenance.currentDeviceName(using: provider) == nil)
        #expect(reads == 3)
    }

    @Test(arguments: ["", " ", "\r\n\t", "\u{00A0}"])
    @MainActor
    func unusableProviderValuesHaveNoFallback(raw: String) {
        #expect(DeviceProvenance.currentDeviceName { raw } == nil)
    }

    @Test("Unicode and internal spaces remain provenance, not rewritten identifiers")
    @MainActor
    func preservesSuppliedUnicode() {
        #expect(
            DeviceProvenance.currentDeviceName { "  Equipo de prueba 🪝  uno \n" }
                == "Equipo de prueba 🪝  uno")
    }

    @Test("Device provenance reads are supplied by the app shell")
    func coreHasNoDevicePlatformReads() throws {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(
            contentsOf: package.appendingPathComponent(
                "Sources/GanchoAppCore/DeviceProvenance.swift"),
            encoding: .utf8)
        for forbidden in ["import UIKit", "UIDevice.current", "Host.current()"] {
            #expect(
                source.contains(forbidden) == false, "AppCore must not discover the host device")
        }
    }

}
