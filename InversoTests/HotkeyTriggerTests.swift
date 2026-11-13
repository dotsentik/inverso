import Carbon
import XCTest

@testable import Inverso

final class HotkeyTriggerTests: XCTestCase {

    private let keyS = UInt16(kVK_ANSI_S)

    // MARK: - KeyChordTrigger

    func testChord_MatchesExactModifiers() {
        var trigger = KeyChordTrigger(keyCode: keyS, modifiers: .option)
        XCTAssertTrue(trigger.handleKeyDown(keyCode: keyS, modifierFlags: .option, timestamp: 0))
        XCTAssertFalse(trigger.handleKeyDown(keyCode: keyS, modifierFlags: [.option, .shift], timestamp: 0))
        XCTAssertFalse(trigger.handleKeyDown(keyCode: keyS, modifierFlags: [], timestamp: 0))
        XCTAssertFalse(trigger.handleKeyDown(keyCode: UInt16(kVK_ANSI_A), modifierFlags: .option, timestamp: 0))
    }

    func testChord_IgnoresCapsLockFunctionAndNumericPad() {
        var trigger = KeyChordTrigger(keyCode: keyS, modifiers: .option)
        XCTAssertTrue(trigger.handleKeyDown(keyCode: keyS, modifierFlags: [.option, .capsLock], timestamp: 0))
        XCTAssertTrue(
            trigger.handleKeyDown(keyCode: keyS, modifierFlags: [.option, .function, .numericPad], timestamp: 0))
    }

    func testChord_RecordedWithCapsLockStillMatchesWithout() {
        var trigger = KeyChordTrigger(keyCode: keyS, modifiers: [.option, .capsLock])
        XCTAssertEqual(trigger.modifiers, .option)
        XCTAssertTrue(trigger.handleKeyDown(keyCode: keyS, modifierFlags: .option, timestamp: 0))
    }

    func testChord_IsSwallowed() {
        XCTAssertTrue(KeyChordTrigger(keyCode: keyS, modifiers: .option).consumesMatchedKeyDown)
        XCTAssertFalse(DoubleShiftTrigger().consumesMatchedKeyDown)
    }

    // MARK: - DoubleShiftTrigger

    func testDoubleShift_TwoQuickTapsFire() {
        var trigger = DoubleShiftTrigger()
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: .shift, timestamp: 0.0))
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: [], timestamp: 0.05))
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: .shift, timestamp: 0.1))
        XCTAssertTrue(trigger.handleFlagsChanged(modifierFlags: [], timestamp: 0.15))
    }

    func testDoubleShift_SlowTapsDoNotFire() {
        var trigger = DoubleShiftTrigger()
        _ = trigger.handleFlagsChanged(modifierFlags: .shift, timestamp: 0.0)
        _ = trigger.handleFlagsChanged(modifierFlags: [], timestamp: 0.05)
        _ = trigger.handleFlagsChanged(modifierFlags: .shift, timestamp: 1.0)
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: [], timestamp: 1.05))
    }

    func testDoubleShift_ShiftWithLetterIsNotATap() {
        // Typing a capital letter between the taps must not count as a clean Shift tap.
        var trigger = DoubleShiftTrigger()
        _ = trigger.handleFlagsChanged(modifierFlags: .shift, timestamp: 0.0)
        _ = trigger.handleFlagsChanged(modifierFlags: [], timestamp: 0.05)
        _ = trigger.handleFlagsChanged(modifierFlags: .shift, timestamp: 0.1)
        _ = trigger.handleKeyDown(keyCode: UInt16(kVK_ANSI_A), modifierFlags: .shift, timestamp: 0.12)
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: [], timestamp: 0.15))
    }

    func testDoubleShift_WithAnotherModifierDoesNotFire() {
        var trigger = DoubleShiftTrigger()
        _ = trigger.handleFlagsChanged(modifierFlags: .shift, timestamp: 0.0)
        _ = trigger.handleFlagsChanged(modifierFlags: [], timestamp: 0.05)
        _ = trigger.handleFlagsChanged(modifierFlags: .shift, timestamp: 0.1)
        _ = trigger.handleFlagsChanged(modifierFlags: [.shift, .command], timestamp: 0.12)
        XCTAssertFalse(trigger.handleFlagsChanged(modifierFlags: [], timestamp: 0.15))
    }
}
