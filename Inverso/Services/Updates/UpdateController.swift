import AppKit
import Combine
import Sparkle

/// Drives the underlying update mechanism (Sparkle in production, a stub in tests).
@MainActor
protocol UpdaterDriving: UpdaterSettings {
    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> { get }
    func startUpdater()
    func checkForUpdates()
}

extension UpdaterDriving {
    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        Just(false).eraseToAnyPublisher()
    }

    func startUpdater() {}
    func checkForUpdates() {}
}

/// Update checks through Sparkle: the "Check for Updates…" menu item and the automatic
/// check switch in Settings. Sparkle stores the switch in the app's defaults and schedules
/// the checks itself.
@MainActor
final class UpdateController: ObservableObject {

    /// False while a check is running or before the updater has started.
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates: Bool

    private let driver: UpdaterDriving

    /// The app's updater. It does nothing until `start()`.
    convenience init() {
        self.init(driver: SparkleUpdaterDriver())
    }

    init(driver: UpdaterDriving) {
        self.driver = driver
        automaticallyChecksForUpdates = driver.automaticallyChecksForUpdates
        driver.canCheckForUpdatesPublisher.assign(to: &$canCheckForUpdates)
    }

    convenience init(settings: UpdaterSettings) {
        self.init(driver: SettingsUpdaterDriver(settings: settings))
    }

    /// Starts the updater and its schedule. Call once at launch.
    func start() {
        // Unit tests run inside the app; they must not check for updates.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        driver.startUpdater()
        Log.app.info(
            "Updater started, automatic checks \(self.automaticallyChecksForUpdates ? "on" : "off", privacy: .public)")
    }

    func checkForUpdates() {
        Log.app.info("Checking for updates (user)")
        driver.checkForUpdates()
    }

    /// Turning checks on also restores the interval, in case an older version stored another one.
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        if enabled {
            driver.updateCheckInterval = UpdateConfig.checkInterval
        }
        driver.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = driver.automaticallyChecksForUpdates
        Log.app.info("Automatic update checks \(enabled ? "enabled" : "disabled", privacy: .public)")
    }

    // MARK: - Error Logging

    /// Errors of the appcast phase (fetching or parsing the feed); "no update found" is not one.
    nonisolated static func isFeedError(_ error: NSError) -> Bool {
        error.domain == SUSparkleErrorDomain && (1000..<2000).contains(error.code)
            && error.code != Int(SUError.noUpdateError.rawValue)
    }

    /// Domains and codes of the error and its underlying errors, plus the feed's HTTP status.
    /// No descriptions: they may contain URLs or paths.
    nonisolated static func feedErrorSummary(_ error: NSError, httpStatus: Int?) -> String {
        var parts: [String] = []
        var current: NSError? = error
        while let next = current, parts.count < 5 {
            parts.append("\(next.domain) \(next.code)")
            current = next.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return parts.joined(separator: " <- ") + ", HTTP \(httpStatus.map(String.init) ?? "n/a")"
    }
}

/// Adapts a plain `UpdaterSettings` double into an `UpdaterDriving` instance without Sparkle.
@MainActor
private final class SettingsUpdaterDriver: UpdaterDriving {
    private let settings: UpdaterSettings

    init(settings: UpdaterSettings) {
        self.settings = settings
    }

    var automaticallyChecksForUpdates: Bool {
        get { settings.automaticallyChecksForUpdates }
        set { settings.automaticallyChecksForUpdates = newValue }
    }

    var updateCheckInterval: TimeInterval {
        get { settings.updateCheckInterval }
        set { settings.updateCheckInterval = newValue }
    }
}

/// Production `UpdaterDriving` backed by Sparkle's `SPUStandardUpdaterController`.
/// Defers instantiating Sparkle's controller until the user checks for updates or the
/// background schedule delay elapses, keeping launch and idle footprint minimal.
@MainActor
final class SparkleUpdaterDriver: UpdaterDriving {
    private static let defaultStartupDelay: Duration = .seconds(120)

    private let defaults: UserDefaults
    private let startupDelay: Duration
    private let controllerStarter: (@MainActor () -> Void)?
    private var standardController: SPUStandardUpdaterController?
    /// Sparkle keeps its delegates weakly.
    private var userDriverDelegate: MenuBarAppUserDriverDelegate?
    private var updaterDelegate: FeedErrorLoggingDelegate?
    private let canCheckSubject = CurrentValueSubject<Bool, Never>(false)
    private var cancellable: AnyCancellable?
    private var deferredStartTask: Task<Void, Never>?
    private(set) var isStarted = false

    var isDeferredStartScheduled: Bool {
        deferredStartTask != nil
    }

    init(
        defaults: UserDefaults = .standard,
        startupDelay: Duration = SparkleUpdaterDriver.defaultStartupDelay,
        controllerStarter: (@MainActor () -> Void)? = nil
    ) {
        self.defaults = defaults
        self.startupDelay = startupDelay
        self.controllerStarter = controllerStarter
    }

    @discardableResult
    private func ensureController() -> SPUStandardUpdaterController {
        if let standardController {
            return standardController
        }
        cancelDeferredStart()
        let userDriverDelegate = MenuBarAppUserDriverDelegate()
        let updaterDelegate = FeedErrorLoggingDelegate()
        let controller = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: userDriverDelegate
        )
        self.userDriverDelegate = userDriverDelegate
        self.updaterDelegate = updaterDelegate
        self.standardController = controller
        self.cancellable = controller.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckSubject.send(value)
            }
        if isStarted {
            controller.startUpdater()
        }
        return controller
    }

    private func startScheduledController() {
        cancelDeferredStart()
        if let controllerStarter {
            controllerStarter()
            return
        }
        ensureController()
    }

    private func scheduleDeferredStart() {
        cancelDeferredStart()
        let delay = startupDelay
        deferredStartTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled, let self, self.automaticallyChecksForUpdates else { return }
            self.startScheduledController()
        }
    }

    private func cancelDeferredStart() {
        deferredStartTask?.cancel()
        deferredStartTask = nil
    }

    var automaticallyChecksForUpdates: Bool {
        get {
            if let standardController {
                return standardController.updater.automaticallyChecksForUpdates
            }
            return defaults.object(forKey: SettingsKeys.sparkleEnableAutomaticChecks) as? Bool
                ?? SettingsKeys.Defaults.sparkleEnableAutomaticChecks
        }
        set {
            if let standardController {
                standardController.updater.automaticallyChecksForUpdates = newValue
            } else {
                defaults.set(newValue, forKey: SettingsKeys.sparkleEnableAutomaticChecks)
                if newValue {
                    if isStarted {
                        scheduleDeferredStart()
                    }
                } else {
                    cancelDeferredStart()
                }
            }
        }
    }

    var updateCheckInterval: TimeInterval {
        get {
            if let standardController {
                return standardController.updater.updateCheckInterval
            }
            return defaults.object(forKey: SettingsKeys.sparkleScheduledCheckInterval) as? TimeInterval
                ?? UpdateConfig.checkInterval
        }
        set {
            if let standardController {
                standardController.updater.updateCheckInterval = newValue
            } else {
                defaults.set(newValue, forKey: SettingsKeys.sparkleScheduledCheckInterval)
            }
        }
    }

    var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
        canCheckSubject.eraseToAnyPublisher()
    }

    func startUpdater() {
        isStarted = true
        canCheckSubject.send(true)
        guard automaticallyChecksForUpdates, standardController == nil else {
            standardController?.startUpdater()
            return
        }
        scheduleDeferredStart()
    }

    func checkForUpdates() {
        ensureController().checkForUpdates(nil)
    }
}

/// Logs why fetching the feed failed without making extra network requests outside Sparkle.
private final class FeedErrorLoggingDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        guard UpdateController.isFeedError(error) else { return }
        Log.app.error(
            "Update feed failed: \(UpdateController.feedErrorSummary(error, httpStatus: nil), privacy: .public)")
    }
}

/// The app has no Dock icon and is never frontmost on its own, so a scheduled update alert
/// would open behind the app the user is typing in. Bring the app forward before it shows.
@MainActor
private final class MenuBarAppUserDriverDelegate: NSObject, @preconcurrency SPUStandardUserDriverDelegate {
    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard handleShowingUpdate, !state.userInitiated else { return }
        NSApp.activate()
    }
}
