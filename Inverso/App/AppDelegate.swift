import Cocoa
import Darwin

/// Starts the app: loads the keyboard layouts, starts the conversion coordinator and asks
/// for the permissions it needs. The conversion itself lives in ConversionCoordinator.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var hasLoadedInitialSystemLayouts = false

    private(set) lazy var settingsManager: SettingsManager = {
        ensureInitialSystemLayoutsLoaded()
        return SettingsManager()
    }()
    private(set) lazy var l10n = LocalizationManager()
    private(set) lazy var conversionLogStore = ConversionLogStore()
    private(set) lazy var conversionHUD = ConversionHUD()
    private(set) lazy var inputSourceMonitor = InputSourceMonitor()
    private(set) lazy var updateController = UpdateController()
    private(set) lazy var launchAtLoginHelper = LaunchAtLoginHelper()
    private(set) lazy var conversionCoordinator = ConversionCoordinator(
        settingsManager: settingsManager,
        l10n: l10n,
        conversionLogStore: self.conversionLogStore,
        hud: self.conversionHUD
    )

    /// Value of kTISNotifyEnabledKeyboardInputSourcesChanged (the C global is not concurrency-safe).
    private static let enabledInputSourcesChanged = Notification.Name(
        "com.apple.Carbon.TISNotifyEnabledKeyboardInputSourcesChanged")

    private func ensureInitialSystemLayoutsLoaded() {
        guard !hasLoadedInitialSystemLayouts else { return }
        hasLoadedInitialSystemLayouts = true
        // Character maps come from the installed layouts; the tables stay as a fallback
        // and cover layouts that only the system maps support.
        LayoutMaps.reloadFromSystem()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Log.app.info("App launched. Bundle: \(Bundle.main.bundlePath, privacy: .public)")
        Log.app.debug("Executable: \(Bundle.main.executablePath ?? "unknown", privacy: .public)")
        Log.app.debug("PID: \(ProcessInfo.processInfo.processIdentifier)")

        ensureInitialSystemLayoutsLoaded()
        _ = settingsManager
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(enabledInputSourcesDidChange),
            name: Self.enabledInputSourcesChanged,
            object: nil
        )

        conversionCoordinator.start()
        updateController.start()

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

        DispatchQueue.main.async {
            malloc_zone_pressure_relief(nil, 0)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            malloc_zone_pressure_relief(nil, 0)
        }
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
            if defaults.bool(forKey: SettingsKeys.openSettingsAtLaunch) {
                Task { @MainActor in
                    try? await Task.sleep(for: launchDelay)
                    NotificationCenter.default.post(name: .openSettingsRequest, object: nil)
                }
            }
            if defaults.bool(forKey: SettingsKeys.demoHUD) {
                let hud = conversionHUD
                hud.displayDuration = .seconds(10)
                hud.backgroundOverride = defaults.string(forKey: SettingsKeys.hudBackground)
                    .flatMap(HUDBackgroundStyle.init(rawValue:))
                Task { @MainActor in
                    try? await Task.sleep(for: launchDelay)
                    hud.show(ConversionHUDContent(input: "ghbdtn", output: "привет", layoutCode: "RU"))
                }
            }
        }
    #endif
}
