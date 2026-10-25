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

    func testKeyChordTriggerMatchesExactKeyCodeAndModifiers() {
        var trigger = KeyChordTrigger(keyCode: 0x31, modifiers: [.option])
        XCTAssertFalse(trigger.monitorsFlagsChanged)
        XCTAssertTrue(trigger.consumesMatchedKeyDown)

        XCTAssertFalse(trigger.handleKeyDown(keyCode: 0x01, modifierFlags: [.option], timestamp: 1.0))
        XCTAssertFalse(trigger.handleKeyDown(keyCode: 0x31, modifierFlags: [.option, .shift], timestamp: 1.1))
        XCTAssertTrue(trigger.handleKeyDown(keyCode: 0x31, modifierFlags: [.option], timestamp: 1.2))
    }

    func testDoubleShiftTriggerFiresOnTwoCleanTapsAndIgnoresInterruptedPresses() {
        var trigger = DoubleShiftTrigger(doubleTapInterval: 0.4)
        XCTAssertTrue(trigger.monitorsFlagsChanged)
        XCTAssertFalse(trigger.consumesMatchedKeyDown)

        // First clean Shift tap at t=1.0
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: [.shift], timestamp: 0.9))
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: [], timestamp: 1.0))

        // Second clean Shift tap within 0.4s fires
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: [.shift], timestamp: 1.2))
        XCTAssertTrue(trigger.handleFlagsChanged(modifierFlags: [], timestamp: 1.25))

        // Pressing a key while Shift is down cancels the tap
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: [.shift], timestamp: 2.0))
        XCTAssertFalse(trigger.handleKeyDown(keyCode: 0x00, modifierFlags: [.shift], timestamp: 2.05))
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: [], timestamp: 2.1))
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: [.shift], timestamp: 2.2))
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: [], timestamp: 2.25))
    }
}
