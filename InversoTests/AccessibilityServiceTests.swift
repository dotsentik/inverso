import XCTest

@testable import Inverso

/// In-memory pasteboard with NSPasteboard's changeCount semantics: every write bumps it.
@MainActor
final class FakePasteboard: PasteboardAccess {
    private(set) var changeCount = 0
    private(set) var text: String?
    /// Every text we wrote via writeTemporary (i.e. our paste contents).
    private(set) var temporaryWrites: [String] = []
    private(set) var restoreCount = 0

    init(text: String? = nil) {
        self.text = text
    }

    func string() -> String? { text }

    func clear() -> Int {
        text = nil
        changeCount += 1
        return changeCount
    }

    func writeTemporary(_ text: String) -> Int {
        self.text = text
        temporaryWrites.append(text)
        changeCount += 1
        return changeCount
    }

    func snapshot() -> PasteboardSnapshot {
        let items = text.map { [PasteboardSnapshot.Item(representations: [.init(type: .string, data: Data($0.utf8))])] }
        return PasteboardSnapshot(items: items ?? [])
    }

    func restore(_ snapshot: PasteboardSnapshot) {
        text = snapshot.items.first?.representations.first.map { String(decoding: $0.data, as: UTF8.self) }
        restoreCount += 1
        changeCount += 1
    }

    /// Another app (or the user) writes to the pasteboard.
    func externalWrite(_ text: String) {
        self.text = text
        changeCount += 1
    }
}

/// Plays the frontmost app: records keystrokes and answers ⌘C with the "selection",
/// optionally after a delay, like a real app processing the event asynchronously.
@MainActor
final class FakeTargetApp: KeystrokeSender {
    let pasteboard: FakePasteboard
    /// Text the app copies on ⌘C; nil = nothing selected, the pasteboard is left untouched.
    var selection: String?
    var copyDelay: Duration = .zero
    private(set) var sent: [Keystroke] = []
    /// How often a sender routed to the key window was requested (overlays).
    private(set) var keyWindowRoutings = 0
    /// Fired synchronously after ⌘V is recorded.
    var onPaste: (() -> Void)?

    init(pasteboard: FakePasteboard, selection: String? = nil) {
        self.pasteboard = pasteboard
        self.selection = selection
    }

    func routedToKeyWindow() -> KeystrokeSender {
        keyWindowRoutings += 1
        return self
    }

    func send(_ keystroke: Keystroke) {
        sent.append(keystroke)
        switch keystroke {
        case .copy:
            guard let selection else { return }
            if copyDelay == .zero {
                pasteboard.externalWrite(selection)
            } else {
                let delay = copyDelay
                Task { @MainActor in
                    try? await Task.sleep(for: delay)
                    self.pasteboard.externalWrite(selection)
                }
            }
        case .paste:
            onPaste?()
        default:
            break
        }
    }
}

/// Accessibility access of the focused element. Default: the app does not support it.
@MainActor
final class FakeSelectedText: SelectedTextAccess {
    var text: String?
    /// Selection length reported via AX; nil = not reported.
    var length: Int?
    var replaceResult: AXReplaceResult = .unchanged
    private(set) var replacements: [String] = []
    private(set) var textReads = 0
    /// Value and selection via AX; when set, the selected text and length come from it.
    var state: OverlayTextSelection.State?
    var rangeSettable = true
    private(set) var rangeWrites: [NSRange] = []

    init(text: String? = nil, length: Int? = nil) {
        self.text = text
        self.length = length
    }

    func selectedText() -> String? {
        textReads += 1
        if let state {
            let selected = (state.value as NSString).substring(with: state.selectedRange)
            return selected.isEmpty ? nil : selected
        }
        return text
    }

    func selectedLength() -> Int? { state?.selectedRange.length ?? length }

    func textState() -> OverlayTextSelection.State? { state }

    func setSelectedRange(_ range: NSRange) -> Bool {
        guard rangeSettable, state != nil else { return false }
        rangeWrites.append(range)
        state?.selectedRange = range
        return true
    }

    func replaceSelectedText(with text: String) async -> AXReplaceResult {
        replacements.append(text)
        return replaceResult
    }
}

@MainActor
final class AccessibilityServiceTests: XCTestCase {

    private static let fastTiming = AccessibilityService.Timing(
        copyTimeout: .milliseconds(200),
        pollInterval: .milliseconds(5),
        selectionSettle: .zero,
        selectionTimeout: .milliseconds(30),
        pasteSettle: .zero
    )

    private func makeService(
        _ app: FakeTargetApp,
        selection: FakeSelectedText = FakeSelectedText(),
        timing: AccessibilityService.Timing = fastTiming,
        clipboardOnly: Bool = false,
        overlayFocused: Bool = false
    ) -> AccessibilityService {
        AccessibilityService(
            pasteboard: app.pasteboard, keystrokes: app, selection: selection, timing: timing,
            isClipboardOnlyApp: { clipboardOnly }, isOverlayFocused: { overlayFocused }
        )
    }

    // MARK: - Spotlight / Open-Save panels

    func testOverlay_ReplacementIsTypedNotPasted() async {
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")
        let selection = FakeSelectedText()
        selection.replaceResult = .replaced

        let ok = await makeService(app, selection: selection, overlayFocused: true).replaceSelection { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(app.sent, [.copy, .typeText("привет")])
        XCTAssertTrue(selection.replacements.isEmpty, "no AX write in an overlay")
        XCTAssertTrue(pasteboard.temporaryWrites.isEmpty)
        XCTAssertEqual(pasteboard.string(), "user clipboard", "original contents restored")
    }

    func testOverlay_ReadsViaAXWithoutTouchingThePasteboard() async {
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")
        let selection = FakeSelectedText(text: "ghbdtn", length: 6)

        let ok = await makeService(app, selection: selection, overlayFocused: true).replaceSelection { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(app.sent, [.typeText("привет")])
        XCTAssertEqual(pasteboard.changeCount, 0)
    }

    func testOverlay_IgnoresClipboardOnlyFrontmostApp() async {
        // Spotlight over VS Code: the frontmost app is clipboard-only, the focused field is not.
        let app = FakeTargetApp(pasteboard: FakePasteboard(), selection: "ghbdtn")
        let selection = FakeSelectedText(text: "ghbdtn", length: 6)

        let ok = await makeService(app, selection: selection, clipboardOnly: true, overlayFocused: true)
            .replaceSelection { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(selection.textReads, 1)
        XCTAssertEqual(app.sent, [.typeText("привет")])
    }

    func testOverlay_LastWordIsSelectedThenTyped() async {
        let app = FakeTargetApp(pasteboard: FakePasteboard(), selection: "ghbdtn")

        let ok = await makeService(app, overlayFocused: true).replaceLastWord { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(app.sent, [.selectWordLeft, .copy, .typeText("привет")])
    }

    func testOverlay_KeystrokesGoToTheKeyWindow() async {
        let app = FakeTargetApp(pasteboard: FakePasteboard(), selection: "ghbdtn")

        _ = await makeService(app, overlayFocused: true).replaceSelection { _ in "привет" }
        XCTAssertEqual(app.keyWindowRoutings, 1)

        _ = await makeService(app).replaceSelection { _ in "привет" }
        XCTAssertEqual(app.keyWindowRoutings, 1, "normal apps: no rerouting")
    }

    func testOverlay_LastWordIsSelectedViaAXRange() async {
        let app = FakeTargetApp(pasteboard: FakePasteboard())
        let selection = FakeSelectedText()
        selection.state = .init(value: "hello ghbdtn", selectedRange: NSRange(location: 12, length: 0))
        var received: String?

        let ok = await makeService(app, selection: selection, overlayFocused: true).replaceLastWord { text in
            received = text
            return "привет"
        }

        XCTAssertTrue(ok)
        XCTAssertEqual(received, "ghbdtn")
        XCTAssertEqual(selection.rangeWrites, [NSRange(location: 6, length: 6)])
        XCTAssertEqual(app.sent, [.typeText("привет")], "no selection keystroke, no ⌘C")
    }

    func testOverlay_LineIsSelectedViaAXRange() async {
        let app = FakeTargetApp(pasteboard: FakePasteboard())
        let selection = FakeSelectedText()
        selection.state = .init(value: "ghbdtn vbh", selectedRange: NSRange(location: 10, length: 0))

        let ok = await makeService(app, selection: selection, overlayFocused: true)
            .replaceLineBeforeCursor { _ in "привет мир" }

        XCTAssertTrue(ok)
        XCTAssertEqual(selection.rangeWrites, [NSRange(location: 0, length: 10)])
        XCTAssertEqual(app.sent, [.typeText("привет мир")])
    }

    func testOverlay_InlineCompletion_DirectConversionLeavesItToSmartMode() async {
        let app = FakeTargetApp(pasteboard: FakePasteboard(), selection: "dtn")
        let selection = FakeSelectedText()
        selection.state = .init(value: "ghbdtn", selectedRange: NSRange(location: 3, length: 3))
        var converterCalled = false

        let ok = await makeService(app, selection: selection, overlayFocused: true).replaceSelection { _ in
            converterCalled = true
            return "x"
        }

        XCTAssertFalse(ok)
        XCTAssertFalse(converterCalled, "the completed tail is not the user's selection")
        XCTAssertEqual(app.sent, [])
    }

    func testOverlay_InlineCompletion_TypedTextIsConverted() async {
        let app = FakeTargetApp(pasteboard: FakePasteboard())
        let selection = FakeSelectedText()
        selection.state = .init(value: "ghbdtn", selectedRange: NSRange(location: 3, length: 3))
        var received: String?

        let ok = await makeService(app, selection: selection, overlayFocused: true).replaceLastWord { text in
            received = text
            return "при"
        }

        XCTAssertTrue(ok)
        XCTAssertEqual(received, "ghb", "the tail is not included")
        XCTAssertEqual(selection.rangeWrites, [NSRange(location: 0, length: 3)])
    }

    func testOverlay_SelectAllIsConvertedAsBefore() async {
        // ⌘A in Spotlight: the user's selection, converted directly
        let app = FakeTargetApp(pasteboard: FakePasteboard())
        let selection = FakeSelectedText()
        selection.state = .init(value: "ghbdtn", selectedRange: NSRange(location: 0, length: 6))

        let ok = await makeService(app, selection: selection, overlayFocused: true).replaceSelection { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertTrue(selection.rangeWrites.isEmpty)
        XCTAssertEqual(app.sent, [.typeText("привет")])
    }

    func testOverlay_RangeNotSettable_FallsBackToKeys() async {
        let app = FakeTargetApp(pasteboard: FakePasteboard(), selection: "ghbdtn")
        let selection = FakeSelectedText()
        selection.state = .init(value: "ghbdtn", selectedRange: NSRange(location: 6, length: 0))
        selection.rangeSettable = false

        let ok = await makeService(app, selection: selection, overlayFocused: true).replaceLastWord { _ in "привет" }

        // The fake's AX selection stays empty after the keystroke: as in a field without AX updates
        XCTAssertFalse(ok)
        XCTAssertEqual(app.sent.first, .selectWordLeft)
        XCTAssertEqual(app.keyWindowRoutings, 1)
    }

    func testOverlay_NotConverted_RestoresTheSelection() async {
        let app = FakeTargetApp(pasteboard: FakePasteboard())
        let selection = FakeSelectedText()
        selection.state = .init(value: "hello", selectedRange: NSRange(location: 5, length: 0))

        let ok = await makeService(app, selection: selection, overlayFocused: true).replaceLastWord { _ in nil }

        XCTAssertFalse(ok)
        XCTAssertEqual(selection.rangeWrites, [NSRange(location: 0, length: 5), NSRange(location: 5, length: 0)])
        XCTAssertEqual(app.sent, [], "no → keystroke")
    }

    func testOverlay_NothingBeforeTheCursor() async {
        let app = FakeTargetApp(pasteboard: FakePasteboard())
        let selection = FakeSelectedText()
        selection.state = .init(value: "", selectedRange: NSRange(location: 0, length: 0))

        let ok = await makeService(app, selection: selection, overlayFocused: true).replaceLastWord { _ in "x" }

        XCTAssertFalse(ok)
        XCTAssertEqual(app.sent, [])
    }

    // MARK: - Selected text

    func testSelectedText_IsConvertedAndPasted() async {
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")
        var pasted: String?
        app.onPaste = { pasted = pasteboard.string() }
        var received: String?

        let ok = await makeService(app).replaceSelection { text in
            received = text
            return "привет"
        }

        XCTAssertTrue(ok)
        XCTAssertEqual(received, "ghbdtn")
        XCTAssertEqual(pasted, "привет")
        XCTAssertEqual(app.sent, [.copy, .paste])
        XCTAssertEqual(pasteboard.string(), "user clipboard", "original contents restored")
    }

    func testNoSelection_ReturnsFalseAndRestores() async {
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: nil)
        var converterCalled = false

        let ok = await makeService(app).replaceSelection { _ in
            converterCalled = true
            return "x"
        }

        XCTAssertFalse(ok)
        XCTAssertFalse(converterCalled)
        XCTAssertEqual(app.sent, [.copy], "no paste, no deselect for an explicit selection")
        XCTAssertEqual(pasteboard.string(), "user clipboard")
    }

    func testConverterReturnsNil_NoPasteAndRestores() async {
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "hello")

        let ok = await makeService(app).replaceSelection { _ in nil }

        XCTAssertFalse(ok)
        XCTAssertEqual(app.sent, [.copy])
        XCTAssertEqual(pasteboard.string(), "user clipboard")
        XCTAssertTrue(pasteboard.temporaryWrites.isEmpty)
    }

    // MARK: - Waiting for the pasteboard instead of a fixed delay

    func testSlowCopy_IsAwaitedUntilChangeCountChanges() async {
        // The app needs 120 ms to answer ⌘C; the chain waits for changeCount, not a fixed delay.
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")
        app.copyDelay = .milliseconds(120)
        var timing = Self.fastTiming
        timing.copyTimeout = .seconds(2)

        var received: String?
        let ok = await makeService(app, timing: timing).replaceSelection { text in
            received = text
            return "привет"
        }

        XCTAssertTrue(ok)
        XCTAssertEqual(received, "ghbdtn")
    }

    func testFastCopy_DoesNotWaitForTimeout() async {
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")
        var timing = Self.fastTiming
        timing.copyTimeout = .seconds(5)

        let start = ContinuousClock.now
        let ok = await makeService(app, timing: timing).replaceSelection { _ in "привет" }
        let elapsed = ContinuousClock.now - start

        XCTAssertTrue(ok)
        XCTAssertLessThan(elapsed, .seconds(1), "finished as soon as the pasteboard changed")
    }

    func testCopyTimeout_GivesUp() async {
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "late")
        app.copyDelay = .seconds(1)
        var timing = Self.fastTiming
        timing.copyTimeout = .milliseconds(50)

        let start = ContinuousClock.now
        let ok = await makeService(app, timing: timing).replaceSelection { _ in "x" }
        let elapsed = ContinuousClock.now - start

        XCTAssertFalse(ok)
        XCTAssertLessThan(elapsed, .milliseconds(900), "did not wait for the late copy")
    }

    func testWaitForPasteboardChange_ReturnsOnCancellation() async {
        let pasteboard = FakePasteboard()
        let service = makeService(FakeTargetApp(pasteboard: pasteboard))
        let count = pasteboard.changeCount

        let task = Task { await service.waitForPasteboardChange(from: count, timeout: .seconds(10)) }
        task.cancel()
        let changed = await task.value

        XCTAssertFalse(changed)
    }

    func testMainActorStaysResponsiveWhileWaiting() async {
        // While the chain waits for ⌘C, other main-actor work must keep running.
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")
        app.copyDelay = .milliseconds(100)
        var timing = Self.fastTiming
        timing.copyTimeout = .seconds(2)
        let service = makeService(app, timing: timing)

        var ticks = 0
        let ticker = Task { @MainActor in
            while !Task.isCancelled {
                ticks += 1
                try? await Task.sleep(for: .milliseconds(10))
            }
        }
        _ = await service.replaceSelection { _ in "привет" }
        ticker.cancel()

        XCTAssertGreaterThan(ticks, 3)
    }

    // MARK: - Smart selection

    func testLastWord_SelectsCopiesAndPastes() async {
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")

        let ok = await makeService(app).replaceLastWord { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(app.sent, [.selectWordLeft, .copy, .paste])
    }

    func testLastWord_NothingToConvert_Deselects() async {
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "hello")

        let ok = await makeService(app).replaceLastWord { _ in nil }

        XCTAssertFalse(ok)
        XCTAssertEqual(app.sent, [.selectWordLeft, .copy, .rightArrow])
    }

    func testLine_SelectsToLineStart() async {
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "hello ghbdtn")

        let ok = await makeService(app).replaceLineBeforeCursor { _ in "hello привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(app.sent, [.selectToLineStart, .copy, .paste])
    }

    func testLine_EmptyLine_Deselects() async {
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard, selection: nil)

        let ok = await makeService(app).replaceLineBeforeCursor { _ in "x" }

        XCTAssertFalse(ok)
        XCTAssertEqual(app.sent, [.selectToLineStart, .copy, .rightArrow])
    }

    // MARK: - Restoring the user's pasteboard

    func testPasteContentsAreWrittenAsTemporary() async {
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")

        _ = await makeService(app).replaceSelection { _ in "привет" }

        XCTAssertEqual(pasteboard.temporaryWrites, ["привет"])
    }

    func testUserCopyDuringPaste_IsNotOverwritten() async {
        let pasteboard = FakePasteboard(text: "old clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")
        // The user copies something right after our ⌘V, before we restore.
        app.onPaste = { pasteboard.externalWrite("fresh user copy") }
        var timing = Self.fastTiming
        timing.pasteSettle = .milliseconds(20)

        let ok = await makeService(app, timing: timing).replaceSelection { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(pasteboard.string(), "fresh user copy")
        XCTAssertEqual(pasteboard.restoreCount, 0)
    }

    func testUntouchedPasteboard_IsRestoredOnce() async {
        let pasteboard = FakePasteboard(text: "old clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")

        _ = await makeService(app).replaceSelection { _ in "привет" }

        XCTAssertEqual(pasteboard.string(), "old clipboard")
        XCTAssertEqual(pasteboard.restoreCount, 1)
    }

    func testEmptyCopy_IsOurWriteAndIsRestored() async {
        // The app answers ⌘C with an empty string: changeCount moves, but because of our ⌘C,
        // so the user's contents are still restored.
        let pasteboard = FakePasteboard(text: "old clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "")

        let ok = await makeService(app).replaceLastWord { _ in "x" }

        XCTAssertFalse(ok)
        XCTAssertEqual(app.sent, [.selectWordLeft, .copy, .rightArrow])
        XCTAssertEqual(pasteboard.string(), "old clipboard")
        XCTAssertEqual(pasteboard.restoreCount, 1)
    }

    // MARK: - Accessibility first, pasteboard as fallback

    func testAX_ReadAndReplace_DoesNotTouchPasteboard() async {
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "should not be copied")
        let selection = FakeSelectedText(text: "ghbdtn")
        selection.replaceResult = .replaced
        var received: String?

        let ok = await makeService(app, selection: selection).replaceSelection { text in
            received = text
            return "привет"
        }

        XCTAssertTrue(ok)
        XCTAssertEqual(received, "ghbdtn")
        XCTAssertEqual(selection.replacements, ["привет"])
        XCTAssertEqual(app.sent, [], "no ⌘C, no ⌘V")
        XCTAssertEqual(pasteboard.changeCount, 0, "pasteboard untouched")
        XCTAssertEqual(pasteboard.restoreCount, 0)
    }

    func testAX_ReadWorksButWriteUnchanged_FallsBackToPaste() async {
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard)
        let selection = FakeSelectedText(text: "ghbdtn")
        selection.replaceResult = .unchanged
        var pasted: String?
        app.onPaste = { pasted = pasteboard.string() }

        let ok = await makeService(app, selection: selection).replaceSelection { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(app.sent, [.paste], "read via AX, so no ⌘C")
        XCTAssertEqual(pasted, "привет")
        XCTAssertEqual(pasteboard.temporaryWrites, ["привет"])
        XCTAssertEqual(pasteboard.string(), "user clipboard", "restored after the paste")
    }

    func testAX_WriteChangedUnexpectedly_DoesNotPasteAgain() async {
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard)
        let selection = FakeSelectedText(text: "ghbdtn")
        selection.replaceResult = .unknown

        let ok = await makeService(app, selection: selection).replaceSelection { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(app.sent, [], "no fallback paste: the text could be inserted twice")
        XCTAssertTrue(pasteboard.temporaryWrites.isEmpty)
    }

    func testAX_NoSelection_FallsBackToCopy() async {
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")
        let selection = FakeSelectedText(text: nil)
        selection.replaceResult = .replaced
        var received: String?

        let ok = await makeService(app, selection: selection).replaceSelection { text in
            received = text
            return "привет"
        }

        XCTAssertTrue(ok)
        XCTAssertEqual(received, "ghbdtn", "read via ⌘C")
        XCTAssertEqual(app.sent, [.copy], "written via AX, no ⌘V")
        XCTAssertEqual(selection.replacements, ["привет"])
        XCTAssertEqual(pasteboard.string(), "user clipboard", "restored after our ⌘C")
    }

    func testAX_ConverterNil_NothingWritten() async {
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard)
        let selection = FakeSelectedText(text: "hello")

        let ok = await makeService(app, selection: selection).replaceLastWord { _ in nil }

        XCTAssertFalse(ok)
        XCTAssertEqual(app.sent, [.selectWordLeft, .rightArrow])
        XCTAssertTrue(selection.replacements.isEmpty)
        XCTAssertEqual(pasteboard.changeCount, 0)
    }

    func testAX_LastWord_SelectsThenReplacesViaAX() async {
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard)
        let selection = FakeSelectedText(text: "ghbdtn")
        selection.replaceResult = .replaced

        let ok = await makeService(app, selection: selection).replaceLastWord { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(app.sent, [.selectWordLeft])
        XCTAssertEqual(selection.replacements, ["привет"])
    }

    // MARK: - Empty selection reported via AX

    func testAXEmptySelection_DoesNotCopy() async {
        // CodeMirror copies the whole line on ⌘C without a selection: it must not be pasted at the cursor
        let pasteboard = FakePasteboard(text: "user clipboard")
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn? rfr ltkf&")
        let selection = FakeSelectedText(length: 0)

        let ok = await makeService(app, selection: selection).replaceSelection { _ in "привет, как дела?" }

        XCTAssertFalse(ok)
        XCTAssertEqual(app.sent, [])
        XCTAssertEqual(pasteboard.changeCount, 0)
    }

    func testAXEmptySelectionAfterSelecting_GivesUpWithoutMovingCursor() async {
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "whole line")
        let selection = FakeSelectedText(length: 0)

        let ok = await makeService(app, selection: selection).replaceLineBeforeCursor { _ in "x" }

        XCTAssertFalse(ok)
        XCTAssertEqual(app.sent, [.selectToLineStart])
    }

    func testAXSelectionAppliedLate_IsAwaited() async {
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")
        let selection = FakeSelectedText(length: 0)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(10))
            selection.length = 6
        }

        let ok = await makeService(app, selection: selection).replaceLineBeforeCursor { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(app.sent, [.selectToLineStart, .copy, .paste])
    }

    // MARK: - Clipboard-only apps (Electron)

    func testClipboardOnlyApp_SkipsAXTextAccess() async {
        let pasteboard = FakePasteboard()
        let app = FakeTargetApp(pasteboard: pasteboard, selection: "ghbdtn")
        let selection = FakeSelectedText(text: "ghbdtn", length: 6)
        selection.replaceResult = .replaced
        var pasted: String?
        app.onPaste = { pasted = pasteboard.string() }

        let ok = await makeService(app, selection: selection, clipboardOnly: true).replaceSelection { _ in "привет" }

        XCTAssertTrue(ok)
        XCTAssertEqual(app.sent, [.copy, .paste])
        XCTAssertEqual(pasted, "привет")
        XCTAssertEqual(selection.textReads, 0)
        XCTAssertTrue(selection.replacements.isEmpty)
    }

    func testClipboardOnlyApps_MatchesListedBundleIDs() {
        XCTAssertTrue(ClipboardOnlyApps.matches(bundleID: "md.obsidian", bundleURL: nil))
        XCTAssertTrue(ClipboardOnlyApps.matches(bundleID: "com.microsoft.VSCode", bundleURL: nil))
        XCTAssertFalse(ClipboardOnlyApps.matches(bundleID: "com.apple.Notes", bundleURL: nil))
    }

    func testClipboardOnlyApps_DetectsElectronFramework() throws {
        let bundle = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ElectronTest-\(UUID().uuidString).app")
        defer { try? FileManager.default.removeItem(at: bundle) }
        XCTAssertFalse(ClipboardOnlyApps.matches(bundleID: "com.example.app", bundleURL: bundle))
        try FileManager.default.createDirectory(
            at: bundle.appendingPathComponent("Contents/Frameworks/Electron Framework.framework"),
            withIntermediateDirectories: true
        )
        XCTAssertTrue(ClipboardOnlyApps.matches(bundleID: "com.example.app", bundleURL: bundle))
    }

    // MARK: - AX write verification

    func testVerifier_Replaced() {
        XCTAssertEqual(
            AXReplaceVerifier.result(
                before: "hi ghbdtn!", selectedRange: NSRange(location: 3, length: 6), inserted: "привет",
                after: "hi привет!"),
            .replaced
        )
    }

    func testVerifier_Unchanged() {
        XCTAssertEqual(
            AXReplaceVerifier.result(
                before: "hi ghbdtn!", selectedRange: NSRange(location: 3, length: 6), inserted: "привет",
                after: "hi ghbdtn!"),
            .unchanged
        )
    }

    func testVerifier_UnexpectedChangeOrUnreadable() {
        let range = NSRange(location: 3, length: 6)
        XCTAssertEqual(
            AXReplaceVerifier.result(before: "hi ghbdtn!", selectedRange: range, inserted: "привет", after: "hi !"),
            .unknown)
        XCTAssertEqual(
            AXReplaceVerifier.result(before: "hi ghbdtn!", selectedRange: range, inserted: "привет", after: nil),
            .unknown)
    }

    func testVerifier_UsesUTF16Ranges() {
        // Emoji take two UTF-16 units; AX ranges are in UTF-16.
        XCTAssertEqual(
            AXReplaceVerifier.result(
                before: "👍 ghbdtn", selectedRange: NSRange(location: 3, length: 6), inserted: "привет",
                after: "👍 привет"),
            .replaced
        )
    }
}
