import AppKit

@main
final class GanchoStoreKitHost: NSObject, NSApplicationDelegate {
    static func main() {
        let application = NSApplication.shared
        let delegate = GanchoStoreKitHost()
        application.delegate = delegate
        application.run()
    }
}
