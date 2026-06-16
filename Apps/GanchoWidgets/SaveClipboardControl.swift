import AppIntents
import SwiftUI
import WidgetKit

/// Control Center / Lock Screen / Action Button control: one tap saves the
/// current clipboard into Gancho. Reuses the shared `SaveClipboardIntent`
/// (same capture path as the Action Button and the home-screen widget). iOS
/// shows its standard paste confirmation when the intent reads the pasteboard.
struct SaveClipboardControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SaveClipboard") {
            ControlWidgetButton(action: SaveClipboardIntent()) {
                Label("Save Clipboard", systemImage: "square.and.arrow.down")
            }
        }
        .displayName("Save Clipboard")
    }
}
