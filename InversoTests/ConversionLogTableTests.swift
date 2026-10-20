import XCTest

@testable import Inverso

final class ConversionLogTableTests: XCTestCase {

    private func entry(_ isCorrect: Bool?, at seconds: TimeInterval = 0, input: String = "ghbdtn") -> ConversionLog {
        ConversionLog(
            id: Int64(seconds),
            timestamp: Date(timeIntervalSince1970: seconds),
            inputText: input,
            outputText: "привет",
            sourceLayout: "com.apple.keylayout.US",
            targetLayout: "com.apple.keylayout.RussianWin",
            conversionMode: "direct",
            isCorrect: isCorrect
        )
    }

    func testRatingCycle() {
        XCTAssertEqual(entry(nil).nextRating, true)
        XCTAssertEqual(entry(true).nextRating, false)
        XCTAssertNil(entry(false).nextRating)
    }

    func testRatingSortOrder_UnratedCorrectIncorrect() {
        let sorted = [entry(false, at: 1), entry(nil, at: 2), entry(true, at: 3)]
            .sorted(using: KeyPathComparator(\ConversionLog.ratingSortKey))
        XCTAssertEqual(sorted.map(\.isCorrect), [nil, true, false])
    }

    func testLayoutsDescription_UsesLastIDComponent() {
        XCTAssertEqual(entry(nil).layoutsDescription, "US → RussianWin")
    }

    func testSortByTimestampDescending() {
        let sorted = [entry(nil, at: 1), entry(nil, at: 3), entry(nil, at: 2)]
            .sorted(using: KeyPathComparator(\ConversionLog.timestamp, order: .reverse))
        XCTAssertEqual(sorted.map(\.id), [3, 2, 1])
    }

    func testSortByInputText() {
        let sorted = [entry(nil, at: 1, input: "b"), entry(nil, at: 2, input: "a")]
            .sorted(using: KeyPathComparator(\ConversionLog.inputText))
        XCTAssertEqual(sorted.map(\.inputText), ["a", "b"])
    }
}
