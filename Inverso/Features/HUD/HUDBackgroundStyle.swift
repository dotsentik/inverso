import Foundation

/// How the HUD background is drawn.
enum HUDBackgroundStyle: String {
    /// macOS 26+ Liquid Glass.
    case glass
    /// macOS 15 fallback.
    case material
    /// Reduce Transparency.
    case solid

    static func current(reduceTransparency: Bool) -> HUDBackgroundStyle {
        if reduceTransparency { return .solid }
        if #available(macOS 26, *) { return .glass }
        return .material
    }
}
