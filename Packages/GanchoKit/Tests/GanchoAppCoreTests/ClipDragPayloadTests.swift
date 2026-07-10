import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Drag-out payload — representations and byte mapping")
struct ClipDragPayloadTests {
    @Test("Sensitive clips advertise nothing, whatever their kind")
    func sensitiveNeverDraggable() {
        for kind in ClipContentKind.allCases {
            #expect(
                ClipDragPayload.representations(for: kind, isSensitive: true).isEmpty,
                "a sensitive \(kind.rawValue) clip must not be a drag source")
        }
        #expect(!ClipDragPayload.isDraggable(ClipItem(kind: .secret, isSensitive: true)))
    }

    @Test("Every non-sensitive kind is draggable")
    func nonSensitiveAlwaysDraggable() {
        for kind in ClipContentKind.allCases {
            #expect(
                !ClipDragPayload.representations(for: kind, isSensitive: false).isEmpty,
                "a non-sensitive \(kind.rawValue) clip should offer at least one type")
        }
    }

    @Test("Kinds map to their pasteboard types, highest fidelity first")
    func representationOrder() {
        #expect(
            ClipDragPayload.representations(for: .image, isSensitive: false) == [.pngImage])
        #expect(
            ClipDragPayload.representations(for: .fileReference, isSensitive: false)
                == [.fileURL, .plainText])
        #expect(
            ClipDragPayload.representations(for: .url, isSensitive: false)
                == [.url, .plainText])
        #expect(
            ClipDragPayload.representations(for: .code, isSensitive: false) == [.plainText])
    }

    @Test("plainText maps text through, joins file paths, and refuses blobs")
    func plainTextMapping() {
        #expect(ClipDragPayload.plainText(for: .text("hola")) == "hola")
        #expect(
            ClipDragPayload.plainText(for: .fileReferences(["/tmp/a.txt", "/tmp/b.txt"]))
                == "/tmp/a.txt\n/tmp/b.txt")
        #expect(
            ClipDragPayload.plainText(
                for: .binary(data: Data([0x89]), typeIdentifier: "public.png")) == nil)
    }

    @Test("fileURLs come only from file-reference content")
    func fileURLMapping() {
        let urls = ClipDragPayload.fileURLs(for: .fileReferences(["/tmp/a.txt", "/tmp/b png.txt"]))
        #expect(urls.map(\.path) == ["/tmp/a.txt", "/tmp/b png.txt"])
        #expect(urls.allSatisfy { $0.isFileURL })
        #expect(ClipDragPayload.fileURLs(for: .text("/tmp/a.txt")).isEmpty)
    }
}
