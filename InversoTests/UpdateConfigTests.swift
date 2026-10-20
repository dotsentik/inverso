import XCTest

@testable import Inverso

final class UpdateConfigTests: XCTestCase {

    /// Info.plist of the app (the test host).
    private var info: [String: Any] {
        Bundle.main.infoDictionary ?? [:]
    }

    func testFeedURLIsHTTPSAppcastOnGitHub() {
        let url = UpdateConfig.feedURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host(), "raw.githubusercontent.com")
        XCTAssertEqual(url.lastPathComponent, "appcast.xml")
    }

    func testFeedURLIsInversoRepository() {
        XCTAssertEqual(
            UpdateConfig.feedURL.absoluteString, "https://raw.githubusercontent.com/dotsentik/inverso/main/appcast.xml")
    }

    func testBundleIdentifierAndPublicKey() {
        XCTAssertEqual(Bundle.main.bundleIdentifier, "com.dotsentik.inverso")
        // The update signing key is the same as in 1.2.6
        XCTAssertEqual(info["SUPublicEDKey"] as? String, "f7dz2bQiE04QwadkRu6SoqSxlr8oGR4QYT7d1DkUg/0=")
    }

    func testCheckIntervalIsOneDay() {
        XCTAssertEqual(UpdateConfig.checkInterval, 86_400)
    }

    func testInfoPlistFeedURLMatchesConfig() {
        XCTAssertEqual(info[UpdateConfig.InfoKey.feedURL] as? String, UpdateConfig.feedURL.absoluteString)
    }

    func testInfoPlistIntervalMatchesConfig() {
        let interval = (info[UpdateConfig.InfoKey.scheduledCheckInterval] as? NSNumber)?.doubleValue
        XCTAssertEqual(interval, UpdateConfig.checkInterval)
    }

    func testInfoPlistEnablesAutomaticChecks() {
        XCTAssertEqual(info[UpdateConfig.InfoKey.enableAutomaticChecks] as? Bool, true)
    }

    func testPublicEDKeyIsEd25519Key() throws {
        let key = try XCTUnwrap(info[UpdateConfig.InfoKey.publicEDKey] as? String)
        let data = try XCTUnwrap(Data(base64Encoded: key), "SUPublicEDKey is not base64")
        XCTAssertEqual(data.count, 32)
    }

    /// Sparkle compares CFBundleVersion; it must be a plain number that grows with each release.
    func testBundleVersionIsNumeric() throws {
        let version = try XCTUnwrap(info["CFBundleVersion"] as? String)
        XCTAssertNotNil(Int(version), "CFBundleVersion '\(version)' is not an integer")
    }
}
