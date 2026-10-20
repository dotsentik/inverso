import AppKit
import Sparkle

/// Update checks through Sparkle: the "Check for Updates…" menu item and the automatic
/// check switch in Settings. Sparkle stores the switch in the app's defaults and schedules
/// the checks itself.
@MainActor
final class UpdateController: ObservableObject {

    static let shared = UpdateController()

    /// False while a check is running or before the updater has started.
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates: Bool

    private let settings: UpdaterSettings
    /// nil in tests: only the settings logic runs.
    private let standardController: SPUStandardUpdaterController?
    /// Sparkle keeps its delegates weakly.
    private let userDriverDelegate: MenuBarAppUserDriverDelegate?
    private let updaterDelegate: FeedErrorLoggingDelegate?

    /// The app's updater. It does nothing until `start()`.
    private init() {
        let userDriverDelegate = MenuBarAppUserDriverDelegate()
        let updaterDelegate = FeedErrorLoggingDelegate()
        let standardController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: updaterDelegate,
            userDriverDelegate: userDriverDelegate
        )
        settings = standardController.updater
        self.standardController = standardController
        self.userDriverDelegate = userDriverDelegate
        self.updaterDelegate = updaterDelegate
        automaticallyChecksForUpdates = standardController.updater.automaticallyChecksForUpdates
        standardController.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    init(settings: UpdaterSettings) {
        self.settings = settings
        standardController = nil
        userDriverDelegate = nil
        updaterDelegate = nil
        automaticallyChecksForUpdates = settings.automaticallyChecksForUpdates
    }

    /// Starts the updater and its schedule. Call once at launch.
    func start() {
        // Unit tests run inside the app; they must not check for updates.
        guard let standardController, ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil
        else { return }
        standardController.startUpdater()
        Log.app.info(
            "Updater started, automatic checks \(self.automaticallyChecksForUpdates ? "on" : "off", privacy: .public)")
    }

    func checkForUpdates() {
        Log.app.info("Checking for updates (user)")
        standardController?.checkForUpdates(nil)
    }

    /// Turning checks on also restores the interval, in case an older version stored another one.
    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        if enabled {
            settings.updateCheckInterval = UpdateConfig.checkInterval
        }
        settings.automaticallyChecksForUpdates = enabled
        automaticallyChecksForUpdates = settings.automaticallyChecksForUpdates
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

/// Logs why fetching the feed failed. Sparkle's "Update Error" alert doesn't say whether
/// the feed is missing (404: private repository, unpublished appcast) or unreachable.
private final class FeedErrorLoggingDelegate: NSObject, SPUUpdaterDelegate {
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        let error = error as NSError
        guard UpdateController.isFeedError(error) else { return }
        guard let feedURL = updater.feedURL else {
            Log.app.error(
                "Update feed failed: \(UpdateController.feedErrorSummary(error, httpStatus: nil), privacy: .public)")
            return
        }
        // Sparkle doesn't report the HTTP status; ask the server again, anonymously.
        var request = URLRequest(url: feedURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "HEAD"
        request.httpShouldHandleCookies = false
        URLSession.shared.dataTask(with: request) { _, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode
            Log.app.error(
                "Update feed failed: \(UpdateController.feedErrorSummary(error, httpStatus: status), privacy: .public)")
        }.resume()
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
