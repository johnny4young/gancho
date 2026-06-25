import SwiftUI
import WidgetKit

/// The widget extension's entry point. Bundles the home/lock-screen widget and
/// the Control Center control. The deployment target is iOS 26, so the
/// iOS 18+ `ControlWidget` is always available — no availability fences.
@main
struct GanchoWidgetBundle: WidgetBundle {
    var body: some Widget {
        RecentClipsWidget()
        SaveClipboardControl()
        ClipLiveActivity()
    }
}
