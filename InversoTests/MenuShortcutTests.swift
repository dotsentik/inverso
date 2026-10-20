import SwiftUI
import XCTest

@testable import Inverso

final class MenuShortcutTests: XCTestCase {

    func testLetterHotkeyBecomesKeyEquivalent() throws {
        let shortcut = try XCTUnwrap(MenuShortcut.keyboardShortcut(keyCode: 0x01, modifiers: .option))  // ⌥S
        XCTAssertEqual(shortcut.key, KeyEquivalent("s"))
        XCTAssertEqual(shortcut.modifiers, .option)
    }

    func testAllModifiersAreKept() throws {
        let shortcut = try XCTUnwrap(
            MenuShortcut.keyboardShortcut(keyCode: 0x12, modifiers: [.command, .shift, .control, .option]))  // 1
        XCTAssertEqual(shortcut.key, KeyEquivalent("1"))
        XCTAssertEqual(shortcut.modifiers, [.command, .shift, .control, .option])
    }

    func testKeysWithoutCharacterHaveNoKeyEquivalent() {
        XCTAssertNil(MenuShortcut.keyboardShortcut(keyCode: 0x31, modifiers: .option))  // Space
        XCTAssertNil(MenuShortcut.keyboardShortcut(keyCode: 0x7A, modifiers: .option))  // F1
        XCTAssertNil(MenuShortcut.keyboardShortcut(keyCode: 0x2C, modifiers: .option))  // "/"
    }
}
