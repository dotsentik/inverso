import XCTest

@testable import Inverso

@MainActor
final class URLStaticStringTests: XCTestCase {

    func testBuildsURLFromLiteral() {
        let url = URL(staticString: "https://example.com/path?q=1")
        XCTAssertEqual(url.absoluteString, "https://example.com/path?q=1")
    }

    func testAppURLConstantsAreRemoteHTTPSURLs() {
        // A fallback to a file URL would pass the non-nil check but not this one.
        let urls = [
            UpdateConfig.feedURL,
            AboutPanel.originalProjectURL,
            AboutPanel.originalLicenseURL,
        ]
        for url in urls {
            XCTAssertEqual(url.scheme, "https", url.absoluteString)
            XCTAssertNotNil(url.host(), url.absoluteString)
        }
    }

    func testAccessibilitySettingsURLOpensPrivacyPane() {
        let url = PermissionsView.accessibilitySettingsURL
        XCTAssertEqual(url.scheme, "x-apple.systempreferences")
        XCTAssertTrue(url.absoluteString.hasSuffix("?Privacy_Accessibility"), url.absoluteString)
    }
}
