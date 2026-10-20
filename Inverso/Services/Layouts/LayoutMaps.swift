import Foundation
import Synchronization

/// Character maps of the layouts: read from the system first, the hardcoded tables as fallback.
enum LayoutMaps {

    private struct State {
        var systemMaps: [String: [Character: Character]] = [:]
        var useSystemLayouts = true
    }

    private static let state = Mutex(State())

    /// false = only the hardcoded tables (deterministic; used by tests).
    static var useSystemLayouts: Bool {
        get { state.withLock { $0.useSystemLayouts } }
        set { state.withLock { $0.useSystemLayouts = newValue } }
    }

    static func characterMap(for layoutID: String) -> [Character: Character]? {
        let systemMap = state.withLock { $0.useSystemLayouts ? $0.systemMaps[layoutID] : nil }
        return systemMap ?? LayoutCharacterMap.characterMap(for: layoutID)
    }

    static func setSystemMaps(_ maps: [String: [Character: Character]]) {
        state.withLock { $0.systemMaps = maps }
    }

    /// Rebuilds the maps of all enabled keyboard layouts. Call on launch and when input sources change.
    @MainActor
    static func reloadFromSystem() {
        var maps: [String: [Character: Character]] = [:]
        for source in KeyboardLayoutDetector.keyboardLayoutSources() {
            guard let id = KeyboardLayoutDetector.sourceID(of: source) else { continue }
            if let map = SystemLayoutMapBuilder.characterMap(for: source) {
                maps[id] = map
            } else {
                Log.layouts.info("No usable key layout data for '\(id, privacy: .public)', using table if any")
            }
        }
        setSystemMaps(maps)
        Log.layouts.info("Loaded \(maps.count) keyboard layouts from the system")
    }
}
