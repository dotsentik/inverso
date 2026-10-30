import XCTest

@testable import Inverso

final class AppEnvironmentTests: XCTestCase {

    func testIsRunningTestsInTestHost() {
        XCTAssertTrue(AppEnvironment.isRunningTests)
    }

    func testIsRunningTestsMatchesEnvironmentVariable() {
        XCTAssertEqual(
            AppEnvironment.isRunningTests,
            ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil)
    }
}
