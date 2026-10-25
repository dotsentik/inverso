import Cocoa

/// Starts the app: loads the keyboard layouts, starts the conversion coordinator and asks
/// for the permissions it needs. The conversion itself lives in ConversionCoordinator.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    let settingsManager: SettingsManager
    let l10n: LocalizationManager
    let conversionLogStore: ConversionLogStore
    let conversionHUD: ConversionHUD
    let inputSourceMonitor: InputSourceMonitor
    let updateController: UpdateController
    let launchAtLoginHelper: LaunchAtLoginHelper
    let conversionCoordinator: ConversionCoordinator

    override init() {
        let settingsManager = SettingsManager()
        let l10n = LocalizationManager()
        let conversionLogStore = ConversionLogStore()
        let conversionHUD = ConversionHUD()
        let inputSourceMonitor = InputSourceMonitor()
        let updateController = UpdateController()
        let launchAtLoginHelper = LaunchAtLoginHelper()
        let conversionCoordinator = ConversionCoordinator(
            settingsManager: settingsManager,
            l10n: l10n,
            conversionLogStore: conversionLogStore,
            hud: conversionHUD
        )
        self.settingsManager = settingsManager
        self.l10n = l10n
        self.conversionLogStore = conversionLogStore
        self.conversionHUD = conversionHUD
        self.inputSourceMonitor = inputSourceMonitor
        self.updateController = updateController
        self.launchAtLoginHelper = launchAtLoginHelper
        self.conversionCoordinator = conversionCoordinator
        super.init()
    }

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
