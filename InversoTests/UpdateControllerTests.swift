import Combine
import Sparkle
import XCTest

@testable import Inverso

@MainActor
final class UpdateControllerTests: XCTestCase {

    /// Mimics SPUUpdater's two settings.
    private final class FakeUpdaterSettings: UpdaterSettings {
        var automaticallyChecksForUpdates: Bool
        var updateCheckInterval: TimeInterval

        init(automaticallyChecksForUpdates: Bool, updateCheckInterval: TimeInterval = UpdateConfig.checkInterval) {
            self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
            self.updateCheckInterval = updateCheckInterval
        }
    }

    private final class FakeUpdaterDriver: UpdaterDriving {
        var automaticallyChecksForUpdates: Bool
        var updateCheckInterval: TimeInterval = UpdateConfig.checkInterval
        let canCheckSubject = CurrentValueSubject<Bool, Never>(false)
        var checkForUpdatesCount = 0

        init(automaticallyChecksForUpdates: Bool = true) {
            self.automaticallyChecksForUpdates = automaticallyChecksForUpdates
        }

        var canCheckForUpdatesPublisher: AnyPublisher<Bool, Never> {
            canCheckSubject.eraseToAnyPublisher()
        }

        func checkForUpdates() {
            checkForUpdatesCount += 1
        }
    }

    func testInitialStateComesFromUpdater() {
        XCTAssertTrue(
            UpdateController(settings: FakeUpdaterSettings(automaticallyChecksForUpdates: true))
                .automaticallyChecksForUpdates)
        XCTAssertFalse(
            UpdateController(settings: FakeUpdaterSettings(automaticallyChecksForUpdates: false))
                .automaticallyChecksForUpdates)
    }

    func testDisablingTurnsChecksOff() {
        let settings = FakeUpdaterSettings(automaticallyChecksForUpdates: true)
        let controller = UpdateController(settings: settings)

        controller.setAutomaticallyChecksForUpdates(false)

        XCTAssertFalse(settings.automaticallyChecksForUpdates)
        XCTAssertFalse(controller.automaticallyChecksForUpdates)
    }

    func testDisablingKeepsInterval() {
        let settings = FakeUpdaterSettings(automaticallyChecksForUpdates: true, updateCheckInterval: 3_600)
        let controller = UpdateController(settings: settings)

        controller.setAutomaticallyChecksForUpdates(false)

        XCTAssertEqual(settings.updateCheckInterval, 3_600)
    }

    func testEnablingTurnsChecksOnWithConfiguredInterval() {
        let settings = FakeUpdaterSettings(automaticallyChecksForUpdates: false, updateCheckInterval: 3_600)
        let controller = UpdateController(settings: settings)

        controller.setAutomaticallyChecksForUpdates(true)

        XCTAssertTrue(settings.automaticallyChecksForUpdates)
        XCTAssertTrue(controller.automaticallyChecksForUpdates)
        XCTAssertEqual(settings.updateCheckInterval, UpdateConfig.checkInterval)
    }

    func testToggleRoundTrip() {
        let settings = FakeUpdaterSettings(automaticallyChecksForUpdates: true)
        let controller = UpdateController(settings: settings)

        controller.setAutomaticallyChecksForUpdates(false)
        controller.setAutomaticallyChecksForUpdates(true)

        XCTAssertTrue(settings.automaticallyChecksForUpdates)
        XCTAssertTrue(controller.automaticallyChecksForUpdates)
    }

    /// The published state follows what the updater accepted, not what was asked.
    func testStateReflectsUpdaterAfterChange() {
        final class RefusingSettings: UpdaterSettings {
            var automaticallyChecksForUpdates: Bool {
                get { false }
                set {}
            }
            var updateCheckInterval: TimeInterval = UpdateConfig.checkInterval
        }
        let controller = UpdateController(settings: RefusingSettings())

        controller.setAutomaticallyChecksForUpdates(true)

        XCTAssertFalse(controller.automaticallyChecksForUpdates)
    }

    func testControllerWithoutSparkleCannotCheck() {
        let controller = UpdateController(settings: FakeUpdaterSettings(automaticallyChecksForUpdates: true))
        XCTAssertFalse(controller.canCheckForUpdates)
        controller.checkForUpdates()  // No updater: must not crash
    }

    func testDriverForwardsCanCheckAndManualChecks() {
        let driver = FakeUpdaterDriver()
        let controller = UpdateController(driver: driver)
        XCTAssertFalse(controller.canCheckForUpdates)

        driver.canCheckSubject.send(true)
        XCTAssertTrue(controller.canCheckForUpdates)

        controller.checkForUpdates()
        XCTAssertEqual(driver.checkForUpdatesCount, 1)
    }

    // MARK: - Feed error logging

    func testFeedErrors_ExcludeNoUpdate() {
        XCTAssertTrue(UpdateController.isFeedError(NSError(domain: SUSparkleErrorDomain, code: 1002)))
        XCTAssertTrue(UpdateController.isFeedError(NSError(domain: SUSparkleErrorDomain, code: 1000)))
        XCTAssertFalse(UpdateController.isFeedError(NSError(domain: SUSparkleErrorDomain, code: 1001)))
        XCTAssertFalse(UpdateController.isFeedError(NSError(domain: SUSparkleErrorDomain, code: 2001)))
        XCTAssertFalse(UpdateController.isFeedError(NSError(domain: NSURLErrorDomain, code: 1002)))
    }

    func testFeedErrorSummary_ListsUnderlyingErrorsWithoutDescriptions() {
        let underlying = NSError(
            domain: NSURLErrorDomain, code: NSURLErrorBadServerResponse,
            userInfo: [NSLocalizedDescriptionKey: "secret /Users/someone/path"])
        let error = NSError(
            domain: SUSparkleErrorDomain, code: 1002,
            userInfo: [NSUnderlyingErrorKey: underlying, NSLocalizedDescriptionKey: "An error occurred"])

        let summary = UpdateController.feedErrorSummary(error, httpStatus: 404)

        XCTAssertEqual(summary, "\(SUSparkleErrorDomain) 1002 <- NSURLErrorDomain -1011, HTTP 404")
        XCTAssertFalse(summary.contains("/Users/"))
        XCTAssertTrue(UpdateController.feedErrorSummary(error, httpStatus: nil).hasSuffix("HTTP n/a"))
    }
}
