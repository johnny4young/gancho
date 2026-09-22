import CoreTransferable
import Foundation
import GanchoKit
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

    public init(id: UUID, kind: ClipContentKind, store: any ClipboardStore) {
        self.id = id
        self.kind = kind
        self.store = store
    }

    public static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .image) { item in
            let payload = try await item.load()
            guard case .binary(let data, let type) = payload.content,
                UTType(type)?.conforms(to: .image) == true
            else { throw CocoaError(.fileReadUnknown) }
            return data
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
                guard
                    ClipItem.hash(of: canonical, kind: payload.item.kind)
                        == payload.item.contentHash
                else { throw CocoaError(.fileReadUnknown) }
                return Data(canonical.utf8)
            }
        }
        .exportingCondition { $0.kind != .image }
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
