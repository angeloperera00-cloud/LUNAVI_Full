import CoreGraphics

enum LunaviSpacing {
    static let xxs: CGFloat = 2
    static let xs: CGFloat = 4
    static let s: CGFloat = 8
    static let m: CGFloat = 12
    static let l: CGFloat = 16
    static let xl: CGFloat = 24
    static let xxl: CGFloat = 32

    static let cornerSmall: CGFloat = 6
    static let cornerMedium: CGFloat = 10
    static let hairline: CGFloat = 1

    static let toolbarHeight: CGFloat = 68
    /// Fixed inspector width: the map gets 70–75 % of the width on current iPads.
    static let inspectorWidth: CGFloat = 340
    /// Below this window width the toolbar actions show icons only (labels need ~1,300 pt).
    static let labeledToolbarMinimumWidth: CGFloat = 1_300

    /// Adaptive inspector: about 27 % of the window, between 320 and 400 pt, so the map stays dominant
    /// (≈ 71–75 % of the width) from iPad mini to 13-inch iPad Pro.
    static func inspectorWidth(forWindowWidth width: CGFloat) -> CGFloat {
        min(max((width * 0.27).rounded(), 320), 400)
    }
    static let timelineHeight: CGFloat = 200
    static let minimumTouchTarget: CGFloat = 44
    /// Below this window width the inspector becomes a sheet.
    static let compactWidthBreakpoint: CGFloat = 900
}
