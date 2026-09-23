import CoreTransferable
import Foundation
import GanchoKit
import ImageIO
import UniformTypeIdentifiers

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// The share sheet requests bytes lazily, not the row's cached preview. Only
/// identity/type are advertised; current store metadata authorizes each load.
public struct ClipShareItem: Transferable {
    let id: UUID
    let kind: ClipContentKind
    let store: any ClipboardStore
    let isProtectedText: @Sendable (String) -> Bool

    /// `isProtectedText` classifies rich text whose plain rendering differs
    /// from the classified plain companion; true refuses the export.
    public init(
        id: UUID, kind: ClipContentKind, store: any ClipboardStore,
        isProtectedText: @escaping @Sendable (String) -> Bool
    ) {
        self.id = id
        self.kind = kind
        self.store = store
        self.isProtectedText = isProtectedText
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .png) { item in
            let payload = try await item.load()
            guard case .binary(let data, let type) = payload.content,
                let png = pngData(from: data, typeIdentifier: type)
            else { throw CocoaError(.fileReadUnknown) }
            return png
        }
        .exportingCondition { $0.kind == .image }
        DataRepresentation(exportedContentType: .utf8PlainText) { item in
            let payload = try await item.load()
            switch payload.content {
            case .text(let text): return Data(text.utf8)
            case .fileReferences(let paths): return Data(paths.joined(separator: "\n").utf8)
            case .binary(let data, let type):
                guard UTType(type)?.conforms(to: .rtf) == true else {
                    throw CocoaError(.fileReadUnknown)
                }
                let text = try NSAttributedString(
                    data: data,
                    options: [.documentType: NSAttributedString.DocumentType.rtf],
                    documentAttributes: nil
                ).string
                let canonical = ContentNormalizer.canonicalText(text, kind: payload.item.kind)
                // RTF rendering rarely matches the plain companion byte for
                // byte, so a mismatch is re-classified rather than refused.
                let matchesClassified =
                    ClipItem.hash(of: canonical, kind: payload.item.kind)
                    == payload.item.contentHash
                guard !canonical.isEmpty, matchesClassified || !item.isProtectedText(canonical)
                else { throw CocoaError(.fileReadUnknown) }
                return Data(canonical.utf8)
            }
        }
        .exportingCondition { $0.kind != .image }
    }

    /// PNG passes through; other stored image formats are transcoded so the
    /// share sheet always receives a concrete, declared type.
    static func pngData(from data: Data, typeIdentifier: String) -> Data? {
        guard let type = UTType(typeIdentifier), type.conforms(to: .image) else { return nil }
        if type.conforms(to: .png) { return data }
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }
        let output = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                output, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    private func load() async throws -> ClipSafeDelivery.Payload {
        guard
            let payload = await ClipSafeDelivery.load(
                id: id, metadata: { try await store.item(id: $0) },
                content: { try await store.content(for: $0) }), payload.item.kind == kind
        else { throw CocoaError(.fileReadUnknown) }
        return payload
    }
}
