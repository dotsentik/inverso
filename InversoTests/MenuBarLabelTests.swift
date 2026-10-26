import AppKit
import XCTest

@testable import Inverso

@MainActor
final class MenuBarLabelTests: XCTestCase {

    func testMenuBarIconIsBundled() {
        XCTAssertNotNil(NSImage(named: "MenuBarIcon"))
    }

    func testMenuBarIconIsTemplate() {
        let image = MenuBarLabel.makeIcon()
        XCTAssertTrue(image.isTemplate)
        XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
    }
}
