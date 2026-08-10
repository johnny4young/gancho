import Foundation

#if canImport(UIKit)
    import UIKit
#endif

/// Resolves the user-facing name of THIS device for `ClipItem.sourceDeviceName`
/// — the "where was this copied" provenance the iOS detail view renders and the
/// capture dedupe key `(contentHash, sourceDeviceName)` scopes by.
///
/// The name is plain sync metadata on purpose (same class as
/// `sourceAppBundleID`): it is the OS device name the user set in Settings,
/// independent of any clip's content, and the dedupe/display paths need it
/// without decrypting anything. See docs/SECURITY-MODEL.md for the
/// field-by-field rationale.
///
/// iOS 16+ returns the generic model name ("iPhone") from `UIDevice.current
/// .name` unless the app holds the user-assigned-device-name entitlement.
/// Generic provenance still separates the Mac from the phone; two same-named
/// devices merely share a dedupe scope — exactly what every device did back
/// when this field was always NULL.
public enum DeviceProvenance {
    /// The current device's name, trimmed. Nil when the platform yields
    /// nothing usable, so the column stays NULL instead of storing a blank.
    @MainActor
    public static func currentDeviceName() -> String? {
        #if os(macOS)
            normalized(Host.current().localizedName)
        #elseif canImport(UIKit)
            normalized(UIDevice.current.name)
        #else
            nil
        #endif
    }

    /// Trims whitespace and newlines; empty results collapse to nil. Pure,
    /// so the edge cases are unit-tested without a device.
    static func normalized(_ raw: String?) -> String? {
        guard let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty
        else { return nil }
        return trimmed
    }
}
