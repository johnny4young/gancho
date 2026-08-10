import Testing

@testable import GanchoAppCore

@Suite("DeviceProvenance — capture provenance name")
struct DeviceProvenanceTests {
    @Test("Normalization trims and collapses unusable names to nil")
    func normalization() {
        #expect(DeviceProvenance.normalized("Johnny's Mac") == "Johnny's Mac")
        #expect(DeviceProvenance.normalized("  Johnny's Mac \n") == "Johnny's Mac")
        #expect(DeviceProvenance.normalized("") == nil, "blank must stay NULL, not ''")
        #expect(DeviceProvenance.normalized("   \n ") == nil)
        #expect(DeviceProvenance.normalized(nil) == nil)
    }

    @Test("The host platform yields a normalized name (or an honest nil)")
    @MainActor
    func currentDeviceName() {
        // The value is machine-specific, so assert the contract, not a name:
        // whatever the platform yields is already trimmed and non-empty.
        let name = DeviceProvenance.currentDeviceName()
        #expect(name == DeviceProvenance.normalized(name))
        if let name {
            #expect(!name.isEmpty)
        }
    }
}
