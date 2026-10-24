import SwiftUI

/// Moves the window it sits in. The panel moves from its top strip only (the
/// search bar and toolbar backgrounds), so rows stay free to drag clips onto
/// boards and into other apps.
struct WindowDragArea: View {
    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .gesture(WindowDragGesture())
            .accessibilityHidden(true)
    }
}
