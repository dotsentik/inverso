import ServiceManagement
import XCTest

@testable import Inverso

@MainActor
final class LaunchAtLoginHelperTests: XCTestCase {

    private struct FakeError: LocalizedError {
        var errorDescription: String? { "Operation not permitted" }
    }

    /// Mimics SMAppService: register/unregister change `status` unless they throw.
    private final class FakeLoginItemService: LoginItemService {
        var status: SMAppService.Status
        var statusAfterRegister: SMAppService.Status = .enabled
        var registerError: Error?
        var unregisterError: Error?
        private(set) var registerCalls = 0
        private(set) var unregisterCalls = 0

        init(status: SMAppService.Status) {
            self.status = status
        }

        func register() throws {
            registerCalls += 1
            if let registerError { throw registerError }
            status = statusAfterRegister
        }

        func unregister() throws {
            unregisterCalls += 1
            if let unregisterError { throw unregisterError }
            status = .notRegistered
        }
    }

    private var openedSettings = 0

    private func makeHelper(_ service: FakeLoginItemService) -> LaunchAtLoginHelper {
        openedSettings = 0
        return LaunchAtLoginHelper(
            service: service,
            openLoginItemsSettings: { [unowned self] in
                self.openedSettings += 1
            })
    }

    func testInitialStatusComesFromSystem() {
        XCTAssertTrue(makeHelper(FakeLoginItemService(status: .enabled)).isEnabled)
        XCTAssertFalse(makeHelper(FakeLoginItemService(status: .notRegistered)).isEnabled)
        XCTAssertFalse(makeHelper(FakeLoginItemService(status: .notFound)).isEnabled)
    }

    func testEnableRegisters() {
        let service = FakeLoginItemService(status: .notRegistered)
        let helper = makeHelper(service)

        helper.setEnabled(true)

        XCTAssertEqual(service.registerCalls, 1)
        XCTAssertTrue(helper.isEnabled)
        XCTAssertNil(helper.lastError)
    }

    func testDisableUnregisters() {
        let service = FakeLoginItemService(status: .enabled)
        let helper = makeHelper(service)

        helper.setEnabled(false)

        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertFalse(helper.isEnabled)
        XCTAssertNil(helper.lastError)
    }

    func testRegisterErrorIsReportedAndToggleStaysOff() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registerError = FakeError()
        let helper = makeHelper(service)

        helper.setEnabled(true)

        XCTAssertFalse(helper.isEnabled)
        XCTAssertEqual(helper.lastError, "Operation not permitted")
    }

    func testUnregisterErrorIsReportedAndToggleStaysOn() {
        let service = FakeLoginItemService(status: .enabled)
        service.unregisterError = FakeError()
        let helper = makeHelper(service)

        helper.setEnabled(false)

        XCTAssertTrue(helper.isEnabled)
        XCTAssertEqual(helper.lastError, "Operation not permitted")
    }

    func testErrorIsClearedOnNextAttempt() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.registerError = FakeError()
        let helper = makeHelper(service)
        helper.setEnabled(true)

        service.registerError = nil
        helper.setEnabled(true)

        XCTAssertNil(helper.lastError)
        XCTAssertTrue(helper.isEnabled)
    }

    func testRequiresApprovalIsNotShownAsEnabled() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let helper = makeHelper(service)

        helper.setEnabled(true)

        XCTAssertFalse(helper.isEnabled)
        XCTAssertTrue(helper.requiresApproval)
        XCTAssertNil(helper.lastError)
    }

    func testEnablingWhileAwaitingApprovalOpensSystemSettings() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let helper = makeHelper(service)

        helper.setEnabled(true)

        XCTAssertEqual(openedSettings, 1)
        XCTAssertEqual(service.registerCalls, 0)
        XCTAssertTrue(helper.requiresApproval)
    }

    func testDisablingWhileAwaitingApprovalUnregisters() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let helper = makeHelper(service)

        helper.setEnabled(false)

        XCTAssertEqual(service.unregisterCalls, 1)
        XCTAssertFalse(helper.requiresApproval)
        XCTAssertEqual(openedSettings, 0)
    }

    func testRefreshPicksUpChangesMadeInSystemSettings() {
        let service = FakeLoginItemService(status: .requiresApproval)
        let helper = makeHelper(service)

        service.status = .enabled
        XCTAssertFalse(helper.isEnabled)
        helper.refresh()

        XCTAssertTrue(helper.isEnabled)
        XCTAssertFalse(helper.requiresApproval)
    }
}
