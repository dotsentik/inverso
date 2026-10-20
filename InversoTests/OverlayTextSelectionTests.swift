import XCTest

@testable import Inverso

final class OverlayTextSelectionTests: XCTestCase {

    private func state(_ value: String, _ location: Int, _ length: Int = 0) -> OverlayTextSelection.State {
        OverlayTextSelection.State(value: value, selectedRange: NSRange(location: location, length: length))
    }

    private func range(_ keystroke: Keystroke, _ state: OverlayTextSelection.State) -> NSRange? {
        OverlayTextSelection.rangeBeforeCursor(keystroke, in: state)
    }

    // MARK: - Range before the cursor

    func testWordLeft_AtEnd() {
        XCTAssertEqual(range(.selectWordLeft, state("ghbdtn", 6)), NSRange(location: 0, length: 6))
        XCTAssertEqual(range(.selectWordLeft, state("hello ghbdtn", 12)), NSRange(location: 6, length: 6))
    }

    func testWordLeft_IncludesTrailingWhitespace() {
        // Like ⇧⌥←: the cursor after "ghbdtn " selects the word and the space
        XCTAssertEqual(range(.selectWordLeft, state("hello ghbdtn ", 13)), NSRange(location: 6, length: 7))
    }

    func testWordLeft_PunctuationBelongsToTheWord() {
        // ",." are б and ю in the Russian layout
        XCTAssertEqual(range(.selectWordLeft, state("ok ,.,", 6)), NSRange(location: 3, length: 3))
    }

    func testWordLeft_CursorInTheMiddle() {
        XCTAssertEqual(range(.selectWordLeft, state("ghbdtn vbh", 6)), NSRange(location: 0, length: 6))
    }

    func testLineStart_StopsAtNewline() {
        XCTAssertEqual(range(.selectToLineStart, state("ghbdtn vbh", 10)), NSRange(location: 0, length: 10))
        XCTAssertEqual(range(.selectToLineStart, state("first\nghbdtn", 12)), NSRange(location: 6, length: 6))
    }

    func testNothingBeforeTheCursor() {
        XCTAssertNil(range(.selectWordLeft, state("", 0)))
        XCTAssertNil(range(.selectWordLeft, state("ghbdtn", 0)))
        XCTAssertNil(range(.selectToLineStart, state("first\n", 6)))
    }

    func testOnlySelectionKeystrokesHaveARange() {
        XCTAssertNil(range(.copy, state("ghbdtn", 6)))
    }

    func testCharactersOutsideTheBMPAreNotSplit() {
        let value = "ok 👍ghbdtn"  // 👍 is two UTF-16 units
        let selected = range(.selectWordLeft, state(value, value.utf16.count))
        XCTAssertEqual(selected, NSRange(location: 3, length: 8))
    }

    // MARK: - Inline completion

    func testInlineCompletion_TypedTextOnly() {
        // Typed "ghb", Spotlight completes to "ghbdtn" with "dtn" selected
        let completed = state("ghbdtn", 3, 3)
        XCTAssertTrue(OverlayTextSelection.isInlineCompletion(completed))
        XCTAssertEqual(OverlayTextSelection.cursor(in: completed), 3)
        XCTAssertEqual(range(.selectWordLeft, completed), NSRange(location: 0, length: 3), "the tail is excluded")
        XCTAssertEqual(range(.selectToLineStart, completed), NSRange(location: 0, length: 3))
    }

    func testSelectionNotReachingTheEnd_IsNotACompletion() {
        XCTAssertFalse(OverlayTextSelection.isInlineCompletion(state("ghbdtn vbh", 0, 6)))
        XCTAssertFalse(OverlayTextSelection.isInlineCompletion(state("ghbdtn vbh", 2, 3)))
    }

    // MARK: - The user's own selection

    func testSelectAll_IsTheUsersSelection() {
        // ⌘A: from the start to the end, not a completion
        let all = state("ghbdtn", 0, 6)
        XCTAssertFalse(OverlayTextSelection.isInlineCompletion(all))
        XCTAssertNil(OverlayTextSelection.cursor(in: all))
        XCTAssertNil(range(.selectWordLeft, all))
    }

    func testEmptySelection_IsTheCaret() {
        XCTAssertFalse(OverlayTextSelection.isInlineCompletion(state("ghbdtn", 6)))
        XCTAssertEqual(OverlayTextSelection.cursor(in: state("ghbdtn", 4)), 4)
    }

    func testRangeOutsideTheValue_IsIgnored() {
        XCTAssertNil(OverlayTextSelection.cursor(in: state("ghb", 5)))
        XCTAssertNil(OverlayTextSelection.cursor(in: state("ghb", NSNotFound)))
    }
}
