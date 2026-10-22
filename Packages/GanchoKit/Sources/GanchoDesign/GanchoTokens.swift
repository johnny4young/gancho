import CoreGraphics

/// Design tokens shared by every platform UI. Components consume token names,
/// never bare numbers — see docs/ARCHITECTURE.md and the future
/// DESIGN-SYSTEM.md.
public enum GanchoTokens {
    public enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48
    }

    public enum Radius {
        public static let sm: CGFloat = 6
        public static let card: CGFloat = 8
        public static let md: CGFloat = 10
        public static let lg: CGFloat = 14
        public static let xl: CGFloat = 20
    }

    public enum Stroke {
        public static let hairline: CGFloat = 1
        /// The focus ring's width; it also sits this far outside the control.
        public static let focus: CGFloat = 2
    }

    /// Opaque surface levels: the panel, cards on it, controls on cards.
    public enum SurfaceLevel: Sendable { case panel, card, control }

    /// Four shadow steps; type sizes come from the system text styles behind
    /// `PanelTextStyle` (22 / 15 / 13 / 12 / 11 on the Mac), not from tokens.
    public enum Elevation: Sendable, CaseIterable {
        /// Window, sidebar and rows: hairline only.
        case flat
        /// Cards.
        case card
        /// Hover and floating banners.
        case raised
        /// Menus, overlays and the panel.
        case overlay

        public var radius: CGFloat {
            switch self {
            case .flat: 0
            case .card: 1
            case .raised: 10
            case .overlay: 20
            }
        }

        public var y: CGFloat {
            switch self {
            case .flat: 0
            case .card: 1
            case .raised: 8
            case .overlay: 18
            }
        }

        public var opacity: Double {
            switch self {
            case .flat: 0
            case .card: 0.05
            case .raised: 0.08
            case .overlay: 0.16
            }
        }
    }
}
