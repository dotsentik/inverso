import Foundation
import Synchronization

/// Character maps of the layouts: read from the system first (`SystemLayoutMapBuilder`),
/// with the hardcoded `LayoutCharacterMap` tables as fallback.
/// Caches forward maps, reverse maps, and character sets until input sources change.
struct LayoutMaps: LayoutMapProviding {

    static let shared = LayoutMaps()

    private struct CachedEntry {
        let forward: [Character: Character]
        let reverse: [Character: Character]
        let characterSet: Set<Character>

        init(forward: [Character: Character]) {
            self.forward = forward
            self.reverse = LayoutMapper.reverseMap(forward)
            self.characterSet = Set(forward.values)
        }
    }

    private struct State {
        var systemMaps: [String: [Character: Character]] = [:]
        var cache: [String: CachedEntry] = [:]
        var useSystemLayouts = true
    }

    private static let state = Mutex(State())

    /// false = only the hardcoded tables (deterministic; used by tests).
    static var useSystemLayouts: Bool {
        get { state.withLock { $0.useSystemLayouts } }
        set {
            state.withLock { state in
                guard state.useSystemLayouts != newValue else { return }
                state.useSystemLayouts = newValue
                state.cache.removeAll()
            }
        }
    }

    static func characterMap(for layoutID: String) -> [Character: Character]? {
        cachedEntry(for: layoutID)?.forward
    }

    static func reverseMap(for layoutID: String) -> [Character: Character]? {
        cachedEntry(for: layoutID)?.reverse
    }

    static func characterSet(for layoutID: String) -> Set<Character>? {
        cachedEntry(for: layoutID)?.characterSet
    }

    static func setSystemMaps(_ maps: [String: [Character: Character]]) {
        state.withLock { state in
            state.systemMaps = maps
            state.cache.removeAll()
        }
    }

    static func invalidateCache() {
        state.withLock { $0.cache.removeAll() }
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

    private static func cachedEntry(for layoutID: String) -> CachedEntry? {
        state.withLock { state in
            if let existing = state.cache[layoutID] {
                return existing
            }
            let forward =
                (state.useSystemLayouts ? state.systemMaps[layoutID] : nil)
                ?? LayoutCharacterMap.characterMap(for: layoutID)
            guard let forward else { return nil }
            let entry = CachedEntry(forward: forward)
            state.cache[layoutID] = entry
            return entry
        }
    }

    // MARK: - LayoutMapProviding

    func characterMap(for layoutID: String) -> [Character: Character]? {
        Self.characterMap(for: layoutID)
    }

    func reverseMap(for layoutID: String) -> [Character: Character]? {
        Self.reverseMap(for: layoutID)
    }

    func characterSet(for layoutID: String) -> Set<Character>? {
        Self.characterSet(for: layoutID)
    }
}
