import AppKit

/// Finds UI that takes keyboard focus without becoming the frontmost app: Spotlight's
/// non-activating panel and the Open/Save panels, which AppKit runs out of process. There
/// NSWorkspace.frontmostApplication (and, for Spotlight.app and the panels, the system-wide
/// AX focus) still point into the app behind, so the focused element must be asked from the
/// process that owns the panel.
enum KeyboardFocusOwner {

    /// Hosts the Spotlight panel on newer macOS (seen on macOS 27) and also Siri, whose
    /// banners stay on screen without the keyboard focus.
    static let spotlightHostBundleID = "com.apple.campo"

    /// One on-screen window, as CGWindowListCopyWindowInfo reports it.
    struct Window: Equatable {
        var pid: pid_t
        var layer: Int
        var size: CGSize
        var alpha: Double
    }

    static func isOverlayProcess(bundleID: String?) -> Bool {
        guard let bundleID else { return false }
        return bundleID == "com.apple.Spotlight" || bundleID == spotlightHostBundleID
            || bundleID.hasPrefix("com.apple.appkit.xpc.openAndSavePanelService")
    }

    /// The Spotlight host also shows Siri banners that don't take the keyboard: its window
    /// counts only while the system-wide AX focus is in that process.
    static func needsFocusConfirmation(bundleID: String?) -> Bool {
        bundleID == spotlightHostBundleID
    }

    /// PID of the overlay process that has keyboard focus, or nil if the frontmost app has it.
    static func overlayPID() -> pid_t? {
        guard
            let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
                as? [[String: Any]]
        else { return nil }
        let windows = info.compactMap { entry -> Window? in
            guard let pid = entry[kCGWindowOwnerPID as String] as? pid_t,
                let layer = entry[kCGWindowLayer as String] as? Int,
                let boundsDict = entry[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsDict)
            else { return nil }
            let alpha = entry[kCGWindowAlpha as String] as? Double ?? 1
            return Window(pid: pid, layer: layer, size: bounds.size, alpha: alpha)
        }
        return overlayPID(
            in: windows,
            bundleID: { NSRunningApplication(processIdentifier: $0)?.bundleIdentifier },
            systemFocusPID: systemFocusPID
        )
    }

    /// PID of the app the system-wide AX focus is in.
    private static func systemFocusPID() -> pid_t? {
        var raw: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute as CFString, &raw) == .success,
            let value = raw, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        var pid: pid_t = 0
        guard AXUIElementGetPid(value as! AXUIElement, &pid) == .success else { return nil }  // Type ID checked above
        return pid
    }

    /// `windows` are front to back. An overlay counts only while it is above every normal
    /// window: an Open/Save sheet of an app in the background must not capture the focus.
    /// `systemFocusPID` is asked only for processes that need the focus confirmed.
    static func overlayPID(
        in windows: [Window], bundleID: (pid_t) -> String?, systemFocusPID: () -> pid_t? = { nil }
    ) -> pid_t? {
        for window in windows where window.alpha > 0 && window.size.width > 1 && window.size.height > 1 {
            let bundle = bundleID(window.pid)
            if isOverlayProcess(bundleID: bundle),
                !needsFocusConfirmation(bundleID: bundle) || systemFocusPID() == window.pid
            {
                return window.pid
            }
            // Windows above the normal level (menu bar, floating HUDs, Siri) don't take
            // keyboard focus; the first normal window belongs to the app that has it.
            if window.layer <= 0 { return nil }
        }
        return nil
    }
}
