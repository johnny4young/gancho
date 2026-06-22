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
                // "Drop into the tray" reads as capturing into Gancho better
                // than a generic save glyph. The tinted symbol gives the tile
                // a recognizable color in Control Center.
                Label("Save Clipboard", systemImage: "tray.and.arrow.down.fill")
            }
            .tint(.accentColor)
        }
        .displayName("Save Clipboard")
    }
}
