import Cocoa

/// Starts the app: loads the keyboard layouts, starts the conversion coordinator and asks
/// for the permissions it needs. The conversion itself lives in ConversionCoordinator.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let conversionCoordinator = ConversionCoordinator()

    private let settingsManager = SettingsManager.shared

    /// Value of kTISNotifyEnabledKeyboardInputSourcesChanged (the C global is not concurrency-safe).
    private static let enabledInputSourcesChanged = Notification.Name(
        "com.apple.Carbon.TISNotifyEnabledKeyboardInputSourcesChanged")

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("App launched. Bundle: \(Bundle.main.bundlePath, privacy: .public)")
        Log.app.debug("Executable: \(Bundle.main.executablePath ?? "unknown", privacy: .public)")
        Log.app.debug("PID: \(ProcessInfo.processInfo.processIdentifier)")

        // Character maps come from the installed layouts; the tables stay as a fallback
        // and cover layouts that only the system maps support.
        LayoutMaps.reloadFromSystem()
        settingsManager.refreshSystemLayouts()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(enabledInputSourcesDidChange),
            name: Self.enabledInputSourcesChanged,
            object: nil
        )

        conversionCoordinator.start()
        UpdateController.shared.start()

        let trusted = AccessibilityService.hasAccessibilityPermission
        Log.app.info("Initial AXIsProcessTrusted = \(trusted)")
        if !trusted {
            Log.app.info("Requesting accessibility permission prompt")
            AccessibilityService.requestAccessibilityPermission()
        }

        if settingsManager.conversionFeedback == .notification {
            ConversionCoordinator.requestNotificationAuthorization()
        }

        #if DEBUG
            startDevelopmentAids()
        #endif
    }

    @objc private func enabledInputSourcesDidChange() {
        Log.layouts.info("Enabled input sources changed, reloading layouts")
        LayoutMaps.reloadFromSystem()
        settingsManager.refreshSystemLayouts()
    }

    #if DEBUG
        /// Screenshot helpers: launch with `-LSOpenSettingsAtLaunch YES`, or
        /// `-LSDemoHUD YES [-LSHUDBackground glass|material|solid]`.
        private func startDevelopmentAids() {
            let launchDelay = Duration.milliseconds(500)
            let defaults = UserDefaults.standard
            if defaults.bool(forKey: "LSOpenSettingsAtLaunch") {
                Task { @MainActor in
                    try? await Task.sleep(for: launchDelay)
                    NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
                }
            }
            if defaults.bool(forKey: "LSDemoHUD") {
                let hud = ConversionHUD.shared
                hud.displayDuration = .seconds(10)
                hud.backgroundOverride = defaults.string(forKey: "LSHUDBackground")
                    .flatMap(HUDBackgroundStyle.init(rawValue:))
                Task { @MainActor in
                    try? await Task.sleep(for: launchDelay)
                    hud.show(ConversionHUDContent(input: "ghbdtn", output: "привет", layoutCode: "RU"))
                }
            }
        }
    #endif
}
