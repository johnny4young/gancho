import SwiftUI

extension EnvironmentValues {
    /// True while the enclosing list is scrolling. Rows drop their pointer
    /// hover for that stretch: AppKit sends no exit when content moves under
    /// a still pointer, so a wash would otherwise stay on a row that left.
    @Entry public var listIsScrolling = false
}
