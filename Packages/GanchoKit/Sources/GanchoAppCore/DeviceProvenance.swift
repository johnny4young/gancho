import Foundation

/// Normalizes capture provenance supplied by the platform shell. The name is
/// existing plain sync metadata and scopes the store's content-hash dedupe key;
/// this boundary neither discovers the host device nor changes that contract.
public enum DeviceProvenance {
    /// Reads the supplied provider once per capture. Nil or whitespace-only
    /// names remain nil; no host lookup or cached fallback is performed here.
    @MainActor
    public static func currentDeviceName(using readName: () -> String?) -> String? {
        normalized(readName())
    }

    static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
