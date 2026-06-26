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
        public static let focus: CGFloat = 1.5
    }

    public enum FontSize {
        public static let caption: CGFloat = 11
        public static let body: CGFloat = 13
        public static let title: CGFloat = 15
        public static let largeTitle: CGFloat = 22
    }
}
