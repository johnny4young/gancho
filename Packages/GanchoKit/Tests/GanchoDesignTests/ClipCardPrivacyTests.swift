import GanchoKit
import Testing

@testable import GanchoDesign

@Suite("ClipCard — sensitive content masking")
@MainActor
struct ClipCardPrivacyTests {
    @Test(
        "Sensitive rows hide titles, previews and thumbnails",
        arguments: [ClipContentKind.image, .text, .color])
    func sensitive(_ kind: ClipContentKind) {
        let item = ClipItem(
            kind: kind, title: "Synthetic private title", contentHash: "private", isSensitive: true)
        #expect(ClipCard(item: item).previewsHidden)
    }

    @Test("Secret kinds stay masked when a legacy sensitivity flag is missing")
    func secret() {
        let item = ClipItem(kind: .secret, contentHash: "legacy")
        #expect(ClipCard(item: item).previewsHidden)
    }

    @Test("Ordinary rows follow explicit private mode", arguments: [false, true])
    func ordinary(_ hidden: Bool) {
        let item = ClipItem(kind: .image, contentHash: "ordinary")
        #expect(ClipCard(item: item, previewsHidden: hidden).previewsHidden == hidden)
    }

    @Test("The stored mask shows only for a protected clip, opted in, outside Private Mode")
    func storedMask() {
        let secret = ClipItem(kind: .secret, preview: "●●●● 4Q2v", contentHash: "s")
        let plain = ClipItem(kind: .text, preview: "hello", contentHash: "p")
        #expect(ClipCard(item: secret, showsStoredMask: true).showsStoredMask)
        #expect(!ClipCard(item: secret).showsStoredMask, "the Mac panel keeps its full mask")
        #expect(
            !ClipCard(item: secret, previewsHidden: true, showsStoredMask: true).showsStoredMask)
        #expect(!ClipCard(item: plain, showsStoredMask: true).showsStoredMask)
        #expect(ClipCard(item: secret, showsStoredMask: true).previewsHidden, "still masked")
    }

    @Test("Lock-screen and widget text keep three dots for a protected clip")
    func widgetSurfacesStayMasked() {
        let secret = ClipItem(kind: .secret, preview: "●●●● 4Q2v", contentHash: "s")
        #expect(ClipSafePresentation.displayText(for: secret) == ClipSafePresentation.masked)
    }

    @Test("A device is named only when it is another one")
    func foreignDevice() {
        func item(_ device: String?) -> ClipItem {
            ClipItem(preview: "x", contentHash: "x", sourceDeviceName: device)
        }
        #expect(ClipCard.foreignDeviceName(of: item(nil), current: "iPhone") == nil)
        #expect(ClipCard.foreignDeviceName(of: item("  "), current: "iPhone") == nil)
        #expect(ClipCard.foreignDeviceName(of: item("iPhone"), current: "iPhone ") == nil)
        #expect(
            ClipCard.foreignDeviceName(of: item("Studio Mac"), current: "iPhone") == "Studio Mac")
        #expect(
            ClipCard(item: item("Studio Mac"), currentDeviceName: "iPhone").foreignDevice
                == "Studio Mac")
        #expect(ClipCard(item: item("Studio Mac")).foreignDevice == nil, "not opted in")
        #expect(
            ClipCard(item: item("Studio Mac"), previewsHidden: true, currentDeviceName: "iPhone")
                .foreignDevice == nil, "hidden previews hide the device too")
    }
}
