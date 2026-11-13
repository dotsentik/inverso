import XCTest

@testable import Inverso

@MainActor
final class TextConverterTests: XCTestCase {

    // The converter runs on an isolated SettingsManager with a fixed U.S. + Russian pair and
    // the built-in tables, so results do not depend on the host's enabled input sources.

    private var converter: TextConverter!
    private var previousUseSystemLayouts = true
    private var suiteName = ""

    override func setUp() async throws {
        try await super.setUp()
        previousUseSystemLayouts = LayoutMaps.useSystemLayouts
        LayoutMaps.useSystemLayouts = false
        suiteName = "com.dotsentik.inversoTests.converter.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = SettingsManager(defaults: defaults)
        settings.enabledLayouts = [
            KeyboardLayout(id: "com.apple.keylayout.US", localizedName: "U.S.", languageCode: "en"),
            KeyboardLayout(id: "com.apple.keylayout.Russian", localizedName: "Russian", languageCode: "ru"),
        ]
        converter = TextConverter(
            preferences: settings, mapProvider: LayoutMaps.shared,
            currentLayoutID: { KeyboardLayoutDetector.currentLayout()?.id })
    }

    override func tearDown() async throws {
        converter = nil
        UserDefaults(suiteName: suiteName)?.removePersistentDomain(forName: suiteName)
        LayoutMaps.useSystemLayouts = previousUseSystemLayouts
        try await super.tearDown()
    }

    // MARK: - convert

    func testConvertSelectedText_LatinToRussian() {
        let result = converter.convert("ghbdtn")?.text
        XCTAssertNotNil(result)
        XCTAssertEqual(result, "привет")
    }

    func testConvertSelectedText_RussianToLatin() {
        let result = converter.convert("руддщ")?.text
        XCTAssertNotNil(result)
        XCTAssertEqual(result, "hello")
    }

    func testConvertSelectedText_MultipleWords() {
        let result = converter.convert("ghbdtn rfr ltkf")?.text
        XCTAssertEqual(result, "привет как дела")
    }

    func testConvertSelectedText_EmptyString() {
        let result = converter.convert("")?.text
        // Empty string has no characters to detect source layout → returns nil
        XCTAssertNil(result)
    }

    func testConvertSelectedText_SingleWord() {
        let result = converter.convert("ntrcn")?.text
        XCTAssertEqual(result, "текст")
    }

    // MARK: - Injected map provider

    private struct FakeMaps: LayoutMapProviding {
        let maps: [String: [Character: Character]]
        func characterMap(for layoutID: String) -> [Character: Character]? { maps[layoutID] }
    }

    func testConvertUsesInjectedProviderForTargetSelection() throws {
        let suite = "com.dotsentik.inversoTests.fakeMaps.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(defaults: defaults)
        let ids = ["fake.A", "fake.C", "fake.B"]
        settings.enabledLayouts = ids.map { KeyboardLayout(id: $0, localizedName: $0, languageCode: "xx") }
        let fake = FakeMaps(maps: [
            "fake.A": ["a": "a", "b": "b", "c": "c"],
            "fake.C": ["a": "d", "b": "e", "c": "f"],
            "fake.B": ["a": "α", "b": "β", "c": "γ"],
        ])
        let fakeConverter = TextConverter(preferences: settings, mapProvider: fake, currentLayoutID: { nil })

        let result = fakeConverter.convert("abc")

        XCTAssertEqual(result?.sourceLayoutID, "fake.A")
        XCTAssertEqual(result?.targetLayoutID, "fake.B")
        XCTAssertEqual(result?.text, "αβγ")
    }

    /// The result names the layouts the conversion really used, so the log does not guess them.
    func testConvertReportsOverriddenTargetAndDetectedSource() throws {
        let suite = "com.dotsentik.inversoTests.overrideResult.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
        let settings = SettingsManager(defaults: defaults)
        let ids = ["fake.A", "fake.C", "fake.B"]
        settings.enabledLayouts = ids.map { KeyboardLayout(id: $0, localizedName: $0, languageCode: "xx") }
        settings.targetOverrides = ["fake.A": "fake.C"]
        let fake = FakeMaps(maps: [
            "fake.A": ["a": "a", "b": "b", "c": "c"],
            "fake.C": ["a": "d", "b": "e", "c": "f"],
            "fake.B": ["a": "α", "b": "β", "c": "γ"],
        ])
        let fakeConverter = TextConverter(preferences: settings, mapProvider: fake, currentLayoutID: { nil })

        let result = fakeConverter.convert("abc")

        XCTAssertEqual(result?.sourceLayoutID, "fake.A")
        XCTAssertEqual(result?.targetLayoutID, "fake.C")
        XCTAssertEqual(result?.text, "def")
    }

    // MARK: - looksLikeWrongLayout

    func testLooksLikeWrongLayout_LatinForRussian() {
        // "ghbdtn" is Latin text that should be Cyrillic when converted
        XCTAssertTrue(converter.looksLikeWrongLayout("ghbdtn"))
    }

    func testLooksLikeWrongLayout_CyrillicForLatin() {
        // "руддщ" is Cyrillic that converts to "hello" (Latin)
        XCTAssertTrue(converter.looksLikeWrongLayout("руддщ"))
    }

    func testLooksLikeWrongLayout_CorrectLatin() {
        // "hello" is correct English — converting to Russian gives Cyrillic gibberish "руддщ"
        // BUT "hello" itself is Latin, and "руддщ" is non-Latin, so it would look like wrong layout.
        // Actually, looksLikeWrongLayout checks if converting SWITCHES script.
        // "hello" → RU → "руддщ" → sourceHasLatinOnly && convertedHasNonLatin → true
        // This is expected: without a dictionary, the algorithm can't tell "hello" from "ghbdtn"
        // Both are Latin text that produce Cyrillic when converted.
        // The algorithm relies on context (user pressed the hotkey = they want conversion).
        let result = converter.looksLikeWrongLayout("hello")
        XCTAssertTrue(result, "Any Latin text looks like wrong layout when RU is available (script switches)")
    }

    func testLooksLikeWrongLayout_EmptyString() {
        XCTAssertFalse(converter.looksLikeWrongLayout(""))
    }

    func testLooksLikeWrongLayout_WhitespaceOnly() {
        XCTAssertFalse(converter.looksLikeWrongLayout("   "))
    }

    func testLooksLikeWrongLayout_NumbersOnly() {
        // Numbers don't change script when converted
        XCTAssertFalse(converter.looksLikeWrongLayout("12345"))
    }

    func testLooksLikeWrongLayout_SpecialCharsOnly() {
        XCTAssertFalse(converter.looksLikeWrongLayout("!@#$%"))
    }

    func testLooksLikeWrongLayout_MixedNumbersAndLetters() {
        // "ghbdtn123" has Latin letters → converts to Cyrillic → wrong layout
        XCTAssertTrue(converter.looksLikeWrongLayout("ghbdtn123"))
    }

    // MARK: - Tokenization (tested via findWrongLayoutBoundary)

    func testFindBoundary_AllWrongLayout() {
        let boundary = converter.findWrongLayoutBoundary(in: "ghbdtn rfr ltkf")
        XCTAssertNotNil(boundary)
        XCTAssertEqual(boundary?.keep, "")
        XCTAssertEqual(boundary?.convert, "ghbdtn rfr ltkf")
    }

    func testFindBoundary_MixedLine_CyrillicThenLatin() {
        // The tail is typed in U.S.; "Привет" has letters outside that layout and stays.
        let boundary = converter.findWrongLayoutBoundary(in: "Привет ghbdtn")
        XCTAssertEqual(boundary?.keep, "Привет ")
        XCTAssertEqual(boundary?.convert, "ghbdtn")
    }

    func testFindBoundary_MixedLine_MultipleCyrillicThenLatin() {
        let boundary = converter.findWrongLayoutBoundary(in: "Привет мир ghbdtn rfr")
        XCTAssertEqual(boundary?.keep, "Привет мир ")
        XCTAssertEqual(boundary?.convert, "ghbdtn rfr")
    }

    func testFindBoundary_MixedLine_LatinThenCyrillic() {
        let boundary = converter.findWrongLayoutBoundary(in: "I said руддщ")
        XCTAssertEqual(boundary?.keep, "I said ")
        XCTAssertEqual(boundary?.convert, "руддщ")
    }

    func testFindBoundary_EmptyString() {
        let boundary = converter.findWrongLayoutBoundary(in: "")
        XCTAssertNil(boundary)
    }

    func testFindBoundary_OnlyWhitespace() {
        let boundary = converter.findWrongLayoutBoundary(in: "   ")
        XCTAssertNil(boundary)
    }

    func testFindBoundary_SingleWord_Wrong() {
        let boundary = converter.findWrongLayoutBoundary(in: "ghbdtn")
        XCTAssertNotNil(boundary)
        XCTAssertEqual(boundary?.keep, "")
        XCTAssertEqual(boundary?.convert, "ghbdtn")
    }

    func testFindBoundary_SingleWord_CyrillicWrong() {
        // "руддщ" → "hello" — Cyrillic to Latin = wrong layout
        let boundary = converter.findWrongLayoutBoundary(in: "руддщ")
        XCTAssertNotNil(boundary)
        XCTAssertEqual(boundary?.keep, "")
        XCTAssertEqual(boundary?.convert, "руддщ")
    }

    // MARK: - convertLineGreedily

    func testConvertLineGreedy_AllWrongLayout() {
        let result = converter.convertLineGreedily("ghbdtn rfr ltkf")?.text
        XCTAssertEqual(result, "привет как дела")
    }

    func testConvertLineGreedy_MixedLine() {
        XCTAssertEqual(converter.convertLineGreedily("Привет ghbdtn")?.text, "Привет привет")
        XCTAssertEqual(converter.convertLineGreedily("Привет, как дела? ntcn")?.text, "Привет, как дела? тест")
        XCTAssertEqual(converter.convertLineGreedily("I said руддщ")?.text, "I said hello")
    }

    func testConvertLineGreedy_MixedLine_SegmentsCoverOnlyTheTail() throws {
        let result = try XCTUnwrap(converter.convertLineGreedily("Привет, как дела? ntcn"))
        XCTAssertEqual(result.originalSegment, "ntcn")
        XCTAssertEqual(result.convertedSegment, "тест")
    }

    func testConvertLineGreedy_LastWordDefinesTheTail() {
        // Without a dictionary the last word always counts as the wrong-layout one;
        // earlier words of the other script stay as typed.
        XCTAssertEqual(converter.convertLineGreedily("ntcn Привет")?.text, "ntcn Ghbdtn")
    }

    func testConvertLineGreedy_NothingToConvert_Numbers() {
        let result = converter.convertLineGreedily("12345")?.text
        // Numbers don't look like wrong layout
        XCTAssertNil(result)
    }

    func testConvertLineGreedy_EmptyString() {
        let result = converter.convertLineGreedily("")?.text
        XCTAssertNil(result)
    }

    func testConvertLineGreedy_SingleWrongWord() {
        let result = converter.convertLineGreedily("ghbdtn")?.text
        XCTAssertEqual(result, "привет")
    }

    func testConvertLineGreedy_CyrillicWrongToLatin() {
        let result = converter.convertLineGreedily("руддщ")?.text
        XCTAssertEqual(result, "hello")
    }

    // MARK: - Explicit layout pair

    func testConvertText_ExplicitPair() {
        let result = LayoutMapper.convert(
            text: "ghbdtn",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "привет")
    }

    func testConvertText_UnknownLayout() {
        let result = LayoutMapper.convert(
            text: "test",
            from: "com.apple.keylayout.Japanese",
            to: "com.apple.keylayout.US"
        )
        XCTAssertNil(result)
    }

    // MARK: - Large dataset: looksLikeWrongLayout

    func testLooksLikeWrongLayout_LargeDataset() {
        // All these Latin strings should look like wrong layout (they convert to Cyrillic)
        let wrongLayoutStrings = [
            "ghbdtn",
            "rfr ltkf",
            "lheu",
            "vbh",
            "cjkywt",
            "rjvgm.nth",
            "ghjuhfvvf",
            "ntrcn",
            "rkfdbfnehf",
            "hf,jnf",
            "ljv",
            "xfq",
            "cjj,otybt",
            "cnhjrf",
        ]

        for str in wrongLayoutStrings {
            XCTAssertTrue(
                converter.looksLikeWrongLayout(str),
                "'\(str)' should be detected as wrong layout")
        }
    }

    func testLooksLikeWrongLayout_CyrillicWrongLayout() {
        // All these Cyrillic strings should look like wrong layout (they convert to Latin)
        let wrongLayoutStrings = [
            "руддщ",  // hello
            "цщкдв",  // world
            "еуыеште",  // testing
            "зкщпкфь",  // program
            "ьфсщы",  // macos
        ]

        for str in wrongLayoutStrings {
            XCTAssertTrue(
                converter.looksLikeWrongLayout(str),
                "'\(str)' should be detected as wrong layout")
        }
    }

    // MARK: - findWrongLayoutBoundary with punctuation

    func testFindBoundary_WithTrailingPunctuation() {
        let boundary = converter.findWrongLayoutBoundary(in: "ghbdtn!")
        // "ghbdtn" is a word token, "!" is punctuation token
        XCTAssertNotNil(boundary)
        XCTAssertEqual(boundary?.keep, "")
        XCTAssertEqual(boundary?.convert, "ghbdtn!")
    }

    func testFindBoundary_WithLeadingPunctuation() {
        // The dash is separated from the word by a space, so it is not attached and stays.
        let boundary = converter.findWrongLayoutBoundary(in: "- ghbdtn")
        XCTAssertEqual(boundary?.keep, "- ")
        XCTAssertEqual(boundary?.convert, "ghbdtn")
        XCTAssertEqual(converter.convertLineGreedily("- ghbdtn")?.text, "- привет")
    }

    // MARK: - Edge case: single character

    func testConvertSelectedText_SingleLatinChar() {
        let result = converter.convert("q")?.text
        XCTAssertEqual(result, "й")
    }

    func testConvertSelectedText_SingleCyrillicChar() {
        let result = converter.convert("й")?.text
        XCTAssertEqual(result, "q")
    }

    // MARK: - ISO section key (tables)

    func testConvert_SectionKeyWord() {
        XCTAssertEqual(converter.convert("§krf")?.text, "ёлка")
        XCTAssertEqual(converter.convert("±KRF")?.text, "ЁЛКА")
        XCTAssertEqual(converter.convert("`krf")?.text, "ёлка")
        XCTAssertEqual(converter.convert("ghbdtn §krf")?.text, "привет ёлка")
        // The tables have ё on the grave key too; on ANSI keyboards that is the key it comes from.
        XCTAssertEqual(converter.convert("ёлка")?.text, "`krf")
    }

    func testConvert_SectionKeyAloneTypesALetter() {
        // "§" is the ё key: like "`", it converts alone because the key types a letter.
        XCTAssertEqual(converter.convert("§")?.text, "ё")
        XCTAssertEqual(converter.convert("`")?.text, "ё")
    }

    func testConvertLineGreedy_SectionKeyWord() {
        XCTAssertEqual(converter.convertLineGreedily("§krf")?.text, "ёлка")
        XCTAssertEqual(converter.convertLineGreedily("ghbdtn §krf")?.text, "привет ёлка")
    }

    func testFindBoundary_PunctuationAttachedToConvertedWord() {
        let boundary = converter.findWrongLayoutBoundary(in: "2025 §krf")
        XCTAssertEqual(boundary?.keep, "2025 ")
        XCTAssertEqual(boundary?.convert, "§krf")
        XCTAssertEqual(converter.convertLineGreedily("2025 §krf")?.text, "2025 ёлка")
        XCTAssertEqual(converter.convertLineGreedily("2025 `krf")?.text, "2025 ёлка")
        // Punctuation that is not a letter key stays as typed.
        XCTAssertEqual(converter.convertLineGreedily("2025 (ghbdtn")?.text, "2025 (привет")
    }

    // MARK: - Whole-line tail

    func testFindBoundary_TrailingNumberStaysInTheRun() {
        let boundary = converter.findWrongLayoutBoundary(in: "ghbdtn rfr ltkf 123")
        XCTAssertEqual(boundary?.keep, "")
        XCTAssertEqual(boundary?.convert, "ghbdtn rfr ltkf 123")
    }

    // MARK: - Neutral (digit-only) tokens

    func testConvertLine_TrailingNumberDoesNotBlockConversion() {
        XCTAssertEqual(converter.convertLineGreedily("ghbdtn 45")?.text, "привет 45")
        XCTAssertEqual(converter.convertLineGreedily("это 185")?.text, "'nj 185")
        XCTAssertEqual(converter.convertLineGreedily("это 45")?.text, "'nj 45")
    }

    func testConvertLine_NumberInMiddleStaysInPlace() {
        XCTAssertEqual(converter.convertLineGreedily("ghbdtn 2024 rfr")?.text, "привет 2024 как")
    }

    func testFindBoundary_OnlyNumbers_ReturnsNil() {
        XCTAssertNil(converter.findWrongLayoutBoundary(in: "12345"))
        XCTAssertNil(converter.findWrongLayoutBoundary(in: "12 345"))
    }

    func testFindBoundary_MixedLineWithTrailingNumber_ConvertsOnlyTheTail() {
        let boundary = converter.findWrongLayoutBoundary(in: "Привет ghbdtn 45")
        XCTAssertEqual(boundary?.keep, "Привет ")
        XCTAssertEqual(boundary?.convert, "ghbdtn 45")
    }

    // MARK: - Word validator (greedy line)

    private func converterWithDictionary(_ words: [String: Set<String>]) throws -> TextConverter {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        let settings = SettingsManager(defaults: defaults)
        // A new manager merges in the host's input sources: pin the pair again.
        settings.enabledLayouts = [
            KeyboardLayout(id: "com.apple.keylayout.US", localizedName: "U.S.", languageCode: "en"),
            KeyboardLayout(id: "com.apple.keylayout.Russian", localizedName: "Russian", languageCode: "ru"),
        ]
        return TextConverter(
            preferences: settings, mapProvider: LayoutMaps.shared,
            currentLayoutID: { KeyboardLayoutDetector.currentLayout()?.id },
            wordValidator: FakeWordValidator(words: words))
    }

    func testGreedy_CorrectWordsBeforeTheTailStay() throws {
        let converter = try converterWithDictionary(["ru": ["открой", "файл"], "en": ["config"]])
        XCTAssertEqual(converter.convertLineGreedily("Открой файл сщташп")?.text, "Открой файл config")
        let english = try converterWithDictionary(["en": ["i", "want"], "ru": ["тест"]])
        XCTAssertEqual(english.convertLineGreedily("I want ntcn")?.text, "I want тест")
    }

    func testGreedy_WrongLayoutWordsStillConvertWithDictionary() throws {
        let converter = try converterWithDictionary(["en": ["hello"], "ru": ["привет", "как", "дела"]])
        XCTAssertEqual(converter.convertLineGreedily("ghbdtn rfr ltkf")?.text, "привет как дела")
    }

    func testGreedy_LastWordConvertsEvenIfItIsAWord() throws {
        let converter = try converterWithDictionary(["en": ["hello"]])
        XCTAssertEqual(converter.convertLineGreedily("hello")?.text, "руддщ")
    }

    func testGreedy_WordThatIsAWordBothWaysKeepsConverting() throws {
        // Ambiguous: a real word typed in the source and after conversion. The run goes on.
        let converter = try converterWithDictionary(["en": ["rfr"], "ru": ["как", "тест"]])
        XCTAssertEqual(converter.convertLineGreedily("rfr ntcn")?.text, "как тест")
    }

    func testGreedy_NoDictionaryForTheLanguageFallsBackToScript() throws {
        let converter = try converterWithDictionary([:])
        XCTAssertEqual(converter.convertLineGreedily("Открой сщташп")?.text, "Jnrhjq config")
    }

    func testSpellCheckerValidator_RecognizesWords() throws {
        let validator = SpellCheckerWordValidator()
        guard let isWord = validator.isWord("файл", languageCode: "ru") else {
            throw XCTSkip("No Russian dictionary on this machine")
        }
        XCTAssertTrue(isWord)
        XCTAssertEqual(validator.isWord("сщташп", languageCode: "ru"), false)
        XCTAssertNil(validator.isWord("word", languageCode: "xx"))
    }

    // MARK: - Edge punctuation

    func testEdgePunctuation_StaysAsTyped() {
        XCTAssertEqual(converter.convert("ghbdtn, rfr ltkf?")?.text, "привет, как дела?")
        XCTAssertEqual(converter.convert("ghbdtn. Rfr ltkf")?.text, "привет. Как дела")
        XCTAssertEqual(converter.convert("ntcn:")?.text, "тест:")
        XCTAssertEqual(converter.convert("\"ntcn\"")?.text, "\"тест\"")
        XCTAssertEqual(converter.convert("руддщ, цщкдв.")?.text, "hello, world.")
    }

    func testEdgePunctuation_BetweenLettersConvertsByKey() throws {
        // The inner "." and "," sit between letters; the last "." is at the edge and needs the dictionary.
        XCTAssertEqual(converter.convert("k.,k.")?.text, "любл.")
        let withDictionary = try converterWithDictionary(["ru": ["люблю"]])
        XCTAssertEqual(withDictionary.convert("k.,k.")?.text, "люблю")
    }

    func testEdgePunctuation_DictionaryKeepsLetterAtTheEdge() throws {
        let converter = try converterWithDictionary(["ru": ["хлеб", "это", "знаю", "и", "молоко"], "en": []])
        XCTAssertEqual(converter.convert("[kt, b vjkjrj")?.text, "хлеб и молоко")
        XCTAssertEqual(converter.convert("'nj")?.text, "это")
        XCTAssertEqual(converter.convert("pyf.")?.text, "знаю")
        // Not a word with the letter: the comma stays a comma.
        XCTAssertEqual(converter.convert("ntcn,")?.text, "тест,")
    }

    func testEdgePunctuation_BothWordsTrailingStaysPunctuationLeadingBecomesLetter() throws {
        let converter = try converterWithDictionary(["ru": ["тест", "тестю", "это", "то"]])
        XCTAssertEqual(converter.convert("ntcn.")?.text, "тест.")
        XCTAssertEqual(converter.convert("'nj")?.text, "это")
    }

    func testEdgePunctuation_WithoutDictionaryStaysAsTyped() {
        XCTAssertEqual(converter.convert("[kt,")?.text, "хле,")
    }

    func testEdgePunctuation_GreedyLine() {
        XCTAssertEqual(converter.convertLineGreedily("Ну, ntcn.")?.text, "Ну, тест.")
    }

    // MARK: - Nothing to convert

    func testConvert_UnchangedTextReturnsNil() {
        XCTAssertNil(converter.convert("12345"))
        XCTAssertNil(converter.convert("!!!"))
    }

    func testConvert_SegmentsAreTheWholeText() throws {
        let result = try XCTUnwrap(converter.convert("ghbdtn"))
        XCTAssertEqual(result.originalSegment, "ghbdtn")
        XCTAssertEqual(result.convertedSegment, "привет")
    }

    // MARK: - LayoutSwitchMode

    func testLayoutSwitchMode_Always() {
        XCTAssertTrue(LayoutSwitchMode.always.shouldSwitchLayout(original: "123", converted: "123"))
    }

    func testLayoutSwitchMode_IfLastWordConverted() {
        let mode = LayoutSwitchMode.ifLastWordConverted
        XCTAssertTrue(mode.shouldSwitchLayout(original: "ghbdtn rfr", converted: "привет как"))
        // Digit-only words do not count as the last word.
        XCTAssertTrue(mode.shouldSwitchLayout(original: "ghbdtn 45", converted: "привет 45"))
        // "ü" is on no key of either layout, so the last word did not change.
        XCTAssertFalse(mode.shouldSwitchLayout(original: "ghbdtn ü", converted: "привет ü"))
    }

    func testLayoutSwitchMode_IfAnyWordConverted() {
        let mode = LayoutSwitchMode.ifAnyWordConverted
        XCTAssertTrue(mode.shouldSwitchLayout(original: "ghbdtn ü", converted: "привет ü"))
        XCTAssertFalse(mode.shouldSwitchLayout(original: "ü 45", converted: "ü 45"))
    }

    func testFindBoundary_LeadingNumberStaysInKeep() {
        let boundary = converter.findWrongLayoutBoundary(in: "2025 ghbdtn 45")
        XCTAssertEqual(boundary?.keep, "2025 ")
        XCTAssertEqual(boundary?.convert, "ghbdtn 45")
        XCTAssertEqual(converter.convertLineGreedily("2025 ghbdtn 45")?.text, "2025 привет 45")
    }
}

/// Dictionary of lowercased words per language; a language without an entry has no dictionary.
@MainActor
private final class FakeWordValidator: WordValidating {
    private let words: [String: Set<String>]

    init(words: [String: Set<String>]) {
        self.words = words
    }

    func isWord(_ word: String, languageCode: String) -> Bool? {
        words[languageCode].map { $0.contains(word.lowercased()) }
    }
}
