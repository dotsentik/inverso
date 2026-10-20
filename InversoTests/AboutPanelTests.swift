import AppKit
import XCTest

@testable import Inverso

@MainActor
final class AboutPanelTests: XCTestCase {

    func testShowsOnlyTheShortVersion() {
        let options = AboutPanel.options(l10n: LocalizationManager.shared)

        // Empty build version: no "(7)" after "Version 1.2.7"
        XCTAssertEqual(options[.version] as? String, "")
        // The short version itself still comes from CFBundleShortVersionString
        XCTAssertNil(options[.applicationVersion])
    }

    func testCreditsLinkToTheOriginalProject() throws {
        let credits = try XCTUnwrap(
            AboutPanel.options(l10n: LocalizationManager.shared)[.credits] as? NSAttributedString)
        var links: [URL] = []
        credits.enumerateAttribute(.link, in: NSRange(location: 0, length: credits.length)) { value, _, _ in
            if let url = value as? URL { links.append(url) }
        }
        XCTAssertEqual(links, [AboutPanel.originalProjectURL, AboutPanel.originalLicenseURL])
    }

    func testCreditsNameTheOriginalProjectAndAuthor() throws {
        let l10n = LocalizationManager.shared
        let credits = try XCTUnwrap(AboutPanel.options(l10n: l10n)[.credits] as? NSAttributedString)
        let basedOn = l10n.localized("about.basedOn")
        XCTAssertTrue(basedOn.contains("LangSwitcher"))
        XCTAssertTrue(basedOn.contains("LayoutSwitcher Contributors"))

        let range = (credits.string as NSString).range(of: basedOn)
        XCTAssertNotEqual(range.location, NSNotFound)
        XCTAssertEqual(
            credits.attribute(.link, at: range.location, effectiveRange: nil) as? URL, AboutPanel.originalProjectURL)
    }

    func testOriginalProjectURL() {
        XCTAssertEqual(AboutPanel.originalProjectURL.absoluteString, "https://github.com/reg2005/langSwitcher")
    }
}
