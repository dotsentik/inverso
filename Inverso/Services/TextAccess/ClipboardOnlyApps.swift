import Foundation

/// Electron/Chromium apps report success for kAXSelectedTextAttribute writes without
/// applying them (Obsidian: status 0, value unchanged), so their text goes through ⌘C/⌘V only.
/// Chromium browsers are listed too: every AX call waits for the page process (up to the
/// messaging timeout), which adds up to seconds, and sites overwrite AX writes in search fields.
enum ClipboardOnlyApps {
    static let bundleIDs: Set<String> = [
        "md.obsidian",
        "com.microsoft.VSCode",
        "com.tinyspeck.slackmacgap",
        "com.hnc.Discord",
        "notion.id",
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.dev",
        "com.google.Chrome.canary",
        "com.brave.Browser",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "org.chromium.Chromium",
        "com.yandex.desktop.yandex-browser",
    ]

    private static let electronFrameworkPath = "Contents/Frameworks/Electron Framework.framework"

    static func matches(bundleID: String?, bundleURL: URL?) -> Bool {
        if let bundleID, bundleIDs.contains(bundleID) { return true }
        guard let bundleURL else { return false }
        return FileManager.default.fileExists(atPath: bundleURL.appendingPathComponent(electronFrameworkPath).path)
    }
}
