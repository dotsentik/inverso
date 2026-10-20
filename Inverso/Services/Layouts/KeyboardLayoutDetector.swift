import Carbon
import Foundation

/// Reads and selects the system keyboard layouts through the Carbon Text Input Sources API.
enum KeyboardLayoutDetector {

    private static let unknownLanguage = "unknown"

    /// Used when none of the enabled layouts can be mapped.
    private static let defaultLayouts = [
        KeyboardLayout(id: "com.apple.keylayout.US", localizedName: "U.S.", languageCode: "en"),
        KeyboardLayout(id: "com.apple.keylayout.Russian", localizedName: "Russian", languageCode: "ru"),
    ]

    /// Keyboard layout input sources (not input methods). Enabled ones by default;
    /// `includeAllInstalled` also returns layouts the user has not added.
    static func keyboardLayoutSources(includeAllInstalled: Bool = false) -> [TISInputSource] {
        let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
        guard
            let sources = TISCreateInputSourceList(filter, includeAllInstalled)?.takeRetainedValue()
                as? [TISInputSource]
        else {
            return []
        }
        return sources.filter { source in
            stringProperty(of: source, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String)
        }
    }

    static func sourceID(of source: TISInputSource) -> String? {
        stringProperty(of: source, kTISPropertyInputSourceID)
    }

    /// Enabled layouts that have a character map (from the system or a table),
    /// or `defaultLayouts` if there are none.
    static func installedLayouts() -> [KeyboardLayout] {
        let layouts = keyboardLayoutSources().compactMap { source -> KeyboardLayout? in
            guard let layout = layout(of: source), LayoutMaps.characterMap(for: layout.id) != nil else {
                return nil
            }
            return layout
        }
        return layouts.isEmpty ? defaultLayouts : layouts
    }

    /// The layout currently selected in the system.
    static func currentLayout() -> KeyboardLayout? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return layout(of: source)
    }

    /// Selects the enabled input source with this ID.
    static func switchLayout(to layoutID: String) {
        guard let inputSources = TISCreateInputSourceList(nil, false)?.takeRetainedValue() as? [TISInputSource] else {
            Log.layouts.error("switchLayout: failed to get input source list")
            return
        }
        guard let source = inputSources.first(where: { sourceID(of: $0) == layoutID }) else {
            Log.layouts.error("switchLayout: layout '\(layoutID, privacy: .public)' not found in system sources")
            return
        }
        let status = TISSelectInputSource(source)
        if status == noErr {
            Log.layouts.info("switchLayout: switched to '\(layoutID, privacy: .public)'")
        } else {
            Log.layouts.error("switchLayout: TISSelectInputSource failed with status \(status)")
        }
    }

    // MARK: - Properties

    private static func layout(of source: TISInputSource) -> KeyboardLayout? {
        guard let id = sourceID(of: source), let name = stringProperty(of: source, kTISPropertyLocalizedName) else {
            return nil
        }
        return KeyboardLayout(id: id, localizedName: name, languageCode: languageCode(of: source))
    }

    private static func languageCode(of source: TISInputSource) -> String {
        guard let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceLanguages) else {
            return unknownLanguage
        }
        let languages = Unmanaged<CFArray>.fromOpaque(pointer).takeUnretainedValue() as? [String]
        return languages?.first ?? unknownLanguage
    }

    /// Value of a CFString property. TISGetInputSourceProperty follows the Get rule:
    /// the value is not retained for us.
    private static func stringProperty(of source: TISInputSource, _ key: CFString) -> String? {
        guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
