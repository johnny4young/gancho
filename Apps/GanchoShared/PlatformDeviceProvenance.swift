import Foundation
import GanchoAppCore

#if canImport(UIKit)
    import UIKit
#endif

/// Device-name discovery belongs to the app and capture-extension shells.
/// iOS can return a generic model name without the user-assigned-name entitlement;
/// preserve that behavior instead of requesting more access or inventing an ID.
@MainActor
enum PlatformDeviceProvenance {
    static func currentDeviceName() -> String? {
        DeviceProvenance.currentDeviceName {
            #if os(macOS)
                Host.current().localizedName
            #elseif canImport(UIKit)
                UIDevice.current.name
            #else
                nil
            #endif
        }
    }
}
