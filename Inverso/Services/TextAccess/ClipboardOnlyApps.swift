import AppKit

/// Electron/Chromium apps report success for kAXSelectedTextAttribute writes without
/// applying them (Obsidian: status 0, value unchanged), so their text goes through ⌘C/⌘V only.
enum ClipboardOnlyApps {
    static let bundleIDs: Set<String> = [
        "md.obsidian",
        "com.microsoft.VSCode",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "notion.id",
    ]

    private static let electronFrameworkPath = "Contents/Frameworks/Electron Framework.framework"

    @MainActor
    static func isFrontmost() -> Bool {
        AppRuleRegistry.isClipboardOnlyFrontmost()
    }

    static func matches(bundleID: String?, bundleURL: URL?) -> Bool {
        if let bundleID, bundleIDs.contains(bundleID) { return true }
        guard let bundleURL else { return false }
        return FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent(electronFrameworkPath).path)
    }
}
