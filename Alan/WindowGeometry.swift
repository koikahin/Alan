import CoreGraphics

enum WindowGeometry {
    static func cocoaRect(from accessibilityRect: CGRect, primaryScreen: CGRect) -> CGRect? {
        let coordinates = [accessibilityRect.origin.x, accessibilityRect.origin.y,
                           accessibilityRect.size.width, accessibilityRect.size.height,
                           primaryScreen.origin.x, primaryScreen.origin.y,
                           primaryScreen.size.width, primaryScreen.size.height]
        guard coordinates.allSatisfy(\.isFinite),
              accessibilityRect.size.width > 0, accessibilityRect.size.height > 0,
              primaryScreen.size.width > 0, primaryScreen.size.height > 0 else {
            return nil
        }

        // Both coordinate systems are anchored to the menu-bar display, even
        // when another display extends above it. Never use the desktop's maxY.
        var result = accessibilityRect
        result.origin.y = primaryScreen.maxY - accessibilityRect.maxY
        return result.origin.y.isFinite ? result : nil
    }
}
