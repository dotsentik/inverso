import Foundation

/// Picks the layout to convert into, based on the user's priority order.
enum TargetLayoutResolver {

    /// - Parameters:
    ///   - sourceID: layout the text was typed in
    ///   - ordered: enabled layout IDs in user priority order (highest first)
    ///   - overrides: explicit "source → target" choices from settings
    ///   - mapProvider: provider of layout character maps
    /// - Returns: 1) the explicit override if it is enabled; 2) otherwise the first layout
    ///   by priority with a different script; 3) otherwise the first other layout by priority.
    static func targetID(
        forSource sourceID: String,
        ordered: [String],
        overrides: [String: String] = [:],
        mapProvider: any LayoutMapProviding
    ) -> String? {
        let candidates = ordered.filter { $0 != sourceID }
        if let explicit = overrides[sourceID], candidates.contains(explicit) {
            return explicit
        }
        let sourceScript = LayoutScript.of(layoutID: sourceID, mapProvider: mapProvider)
        if let otherScript = candidates.first(where: {
            LayoutScript.of(layoutID: $0, mapProvider: mapProvider) != sourceScript
        }) {
            return otherScript
        }
        return candidates.first
    }
}
