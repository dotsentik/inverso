import XCTest

@testable import Inverso

final class LayoutMapperTests: XCTestCase {

    // These tests pin the hardcoded tables; system layouts are covered in SystemLayoutMapsTests.
    override func setUp() {
        super.setUp()
        LayoutMaps.useSystemLayouts = false
    }

    override func tearDown() {
        LayoutMaps.useSystemLayouts = true
        super.tearDown()
    }

    // MARK: - LayoutCharacterMap.characterMap(for:)

    func testCharacterMapMatchesUSLayout() {
        let map = LayoutCharacterMap.characterMap(for: "com.apple.keylayout.US")
        XCTAssertNotNil(map, "US layout should be recognized")
    }

    func testCharacterMapMatchesRussianLayout() {
        let map = LayoutCharacterMap.characterMap(for: "com.apple.keylayout.Russian")
        XCTAssertNotNil(map, "Russian layout should be recognized")
    }

    func testCharacterMapMatchesUkrainianLayout() {
        let map = LayoutCharacterMap.characterMap(for: "com.apple.keylayout.Ukrainian")
        XCTAssertNotNil(map, "Ukrainian layout should be recognized")
    }

    func testCharacterMapMatchesGermanLayout() {
        let map = LayoutCharacterMap.characterMap(for: "com.apple.keylayout.German")
        XCTAssertNotNil(map, "German layout should be recognized")
    }

    func testCharacterMapMatchesFrenchLayout() {
        let map = LayoutCharacterMap.characterMap(for: "com.apple.keylayout.French")
        XCTAssertNotNil(map, "French layout should be recognized")
    }

    func testCharacterMapMatchesSpanishLayout() {
        let map = LayoutCharacterMap.characterMap(for: "com.apple.keylayout.Spanish")
        XCTAssertNotNil(map, "Spanish layout should be recognized")
    }

    func testCharacterMapMatchesBritishLayout() {
        let map = LayoutCharacterMap.characterMap(for: "com.apple.keylayout.British")
        XCTAssertNotNil(map, "British layout should be recognized")
    }

    func testCharacterMapMatchesABCLayout() {
        let map = LayoutCharacterMap.characterMap(for: "com.apple.keylayout.ABC")
        XCTAssertNotNil(map, "ABC layout should be recognized")
    }

    func testCharacterMapReturnsNilForUnknownLayout() {
        let map = LayoutCharacterMap.characterMap(for: "com.apple.keylayout.Japanese")
        XCTAssertNil(map, "Unsupported layout should return nil")
    }

    // CRITICAL: Pattern ordering — "russian" contains "us" so Russian must match "russian" not "us"
    func testRussianDoesNotMatchUSPattern() {
        let ruMap = LayoutCharacterMap.characterMap(for: "com.apple.keylayout.Russian")
        let usMap = LayoutCharacterMap.characterMap(for: "com.apple.keylayout.US")
        // Russian map should have Cyrillic characters; US map should not
        XCTAssertNotNil(ruMap)
        XCTAssertNotNil(usMap)
        // Check that 'q' maps to 'й' in Russian, not to 'q' (which would mean US matched)
        XCTAssertEqual(
            ruMap?[Character("q")], Character("й"),
            "Russian layout should map 'q' to 'й', not keep it as 'q'")
        XCTAssertEqual(
            usMap?[Character("q")], Character("q"),
            "US layout should map 'q' to 'q'")
    }

    // MARK: - LayoutMapper.convert() — EN → RU

    func testConvertENtoRU_privet() {
        let result = LayoutMapper.convert(
            text: "ghbdtn",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "привет")
    }

    func testConvertENtoRU_hello() {
        // "руддщ" typed on Russian when meaning "hello" on QWERTY
        let result = LayoutMapper.convert(
            text: "hello",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "руддщ")
    }

    func testConvertENtoRU_kakDela() {
        let result = LayoutMapper.convert(
            text: "rfr ltkf",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "как дела")
    }

    func testConvertENtoRU_drug() {
        let result = LayoutMapper.convert(
            text: "lheu",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "друг")
    }

    func testConvertENtoRU_longPhrase() {
        let result = LayoutMapper.convert(
            text: "ghbdtn rfr ltkf lheu",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "привет как дела друг")
    }

    func testConvertENtoRU_upperCase() {
        let result = LayoutMapper.convert(
            text: "GHBDTN",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "ПРИВЕТ")
    }

    func testConvertENtoRU_mixedCase() {
        let result = LayoutMapper.convert(
            text: "Ghbdtn",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "Привет")
    }

    func testConvertENtoRU_withPunctuation() {
        let result = LayoutMapper.convert(
            text: "ghbdtn!",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        // '!' on QWERTY position maps to '!' in Russian? Check: Shift+1 = '!' in QWERTY, = '!' in Russian
        XCTAssertNotNil(result)
        XCTAssertTrue(result!.hasPrefix("привет"))
    }

    func testConvertENtoRU_numbers() {
        // Numbers are at the same positions, should pass through
        let result = LayoutMapper.convert(
            text: "123",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "123")
    }

    func testConvertENtoRU_spacesPreserved() {
        let result = LayoutMapper.convert(
            text: "  ghbdtn  ",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "  привет  ")
    }

    // MARK: - LayoutMapper.convert() — RU → EN

    func testConvertRUtoEN_rullo() {
        // "руддщ" → "hello"
        let result = LayoutMapper.convert(
            text: "руддщ",
            from: "com.apple.keylayout.Russian",
            to: "com.apple.keylayout.US"
        )
        XCTAssertEqual(result, "hello")
    }

    func testConvertRUtoEN_privet() {
        // "привет" → "ghbdtn"
        let result = LayoutMapper.convert(
            text: "привет",
            from: "com.apple.keylayout.Russian",
            to: "com.apple.keylayout.US"
        )
        XCTAssertEqual(result, "ghbdtn")
    }

    func testConvertRUtoEN_upperCase() {
        let result = LayoutMapper.convert(
            text: "РУДДЩ",
            from: "com.apple.keylayout.Russian",
            to: "com.apple.keylayout.US"
        )
        XCTAssertEqual(result, "HELLO")
    }

    // MARK: - Round-trip tests (EN→RU→EN should return original)

    func testRoundTrip_ENtoRUandBack() {
        let original = "ghbdtn rfr ltkf"
        let toRU = LayoutMapper.convert(
            text: original,
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertNotNil(toRU)
        let backToEN = LayoutMapper.convert(
            text: toRU!,
            from: "com.apple.keylayout.Russian",
            to: "com.apple.keylayout.US"
        )
        XCTAssertEqual(backToEN, original)
    }

    func testRoundTrip_RUtoENandBack() {
        let original = "привет мир"
        let toEN = LayoutMapper.convert(
            text: original,
            from: "com.apple.keylayout.Russian",
            to: "com.apple.keylayout.US"
        )
        XCTAssertNotNil(toEN)
        let backToRU = LayoutMapper.convert(
            text: toEN!,
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(backToRU, original)
    }

    // MARK: - Edge Cases

    func testConvertEmptyString() {
        let result = LayoutMapper.convert(
            text: "",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "")
    }

    func testConvertSingleCharacter() {
        let result = LayoutMapper.convert(
            text: "q",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "й")
    }

    func testConvertOnlySpaces() {
        let result = LayoutMapper.convert(
            text: "   ",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "   ")
    }

    func testConvertNilForUnknownSourceLayout() {
        let result = LayoutMapper.convert(
            text: "test",
            from: "com.apple.keylayout.Japanese",
            to: "com.apple.keylayout.US"
        )
        XCTAssertNil(result)
    }

    func testConvertNilForUnknownTargetLayout() {
        let result = LayoutMapper.convert(
            text: "test",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Japanese"
        )
        XCTAssertNil(result)
    }

    // MARK: - German (QWERTZ) conversions

    func testConvertENtoDE_yz() {
        // QWERTY 'y' → QWERTZ 'z' and vice versa
        let result = LayoutMapper.convert(
            text: "y",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.German"
        )
        XCTAssertEqual(result, "z")
    }

    func testConvertENtoDE_zy() {
        let result = LayoutMapper.convert(
            text: "z",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.German"
        )
        XCTAssertEqual(result, "y")
    }

    // MARK: - French (AZERTY) conversions

    func testConvertENtoFR_qwertyToAzerty() {
        // QWERTY 'q' → AZERTY 'a'
        let result = LayoutMapper.convert(
            text: "q",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.French"
        )
        XCTAssertEqual(result, "a")
    }

    func testConvertENtoFR_aToQ() {
        // QWERTY 'a' → AZERTY 'q'
        let result = LayoutMapper.convert(
            text: "a",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.French"
        )
        XCTAssertEqual(result, "q")
    }

    // MARK: - Ukrainian conversions

    func testConvertENtoUK_privet() {
        // Ukrainian uses a similar layout to Russian but with some differences
        let result = LayoutMapper.convert(
            text: "ghbdsn",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Ukrainian"
        )
        XCTAssertNotNil(result)
        // In Ukrainian: g→п, h→р, b→и, d→в, s→і, n→т
        XCTAssertEqual(result, "привіт")
    }

    // MARK: - detectSourceLayout

    func testDetectSourceLayout_CyrillicText() {
        let detected = LayoutMapper.detectSourceLayout(
            text: "привет",
            candidateLayouts: ["com.apple.keylayout.US", "com.apple.keylayout.Russian"]
        )
        XCTAssertEqual(detected, "com.apple.keylayout.Russian")
    }

    func testDetectSourceLayout_LatinText() {
        let detected = LayoutMapper.detectSourceLayout(
            text: "hello",
            candidateLayouts: ["com.apple.keylayout.US", "com.apple.keylayout.Russian"]
        )
        XCTAssertEqual(detected, "com.apple.keylayout.US")
    }

    func testDetectSourceLayout_WrongLayoutLatin() {
        // "ghbdtn" is Latin — should detect as US source
        let detected = LayoutMapper.detectSourceLayout(
            text: "ghbdtn",
            candidateLayouts: ["com.apple.keylayout.US", "com.apple.keylayout.Russian"]
        )
        XCTAssertEqual(detected, "com.apple.keylayout.US")
    }

    func testDetectSourceLayout_WrongLayoutCyrillic() {
        // "руддщ" is Cyrillic — should detect as Russian source
        let detected = LayoutMapper.detectSourceLayout(
            text: "руддщ",
            candidateLayouts: ["com.apple.keylayout.US", "com.apple.keylayout.Russian"]
        )
        XCTAssertEqual(detected, "com.apple.keylayout.Russian")
    }

    func testDetectSourceLayout_EmptyText() {
        let detected = LayoutMapper.detectSourceLayout(
            text: "",
            candidateLayouts: ["com.apple.keylayout.US", "com.apple.keylayout.Russian"]
        )
        // Empty text should return nil or first layout (score 0 for all)
        // Implementation returns nil when bestScore is 0
        XCTAssertNil(detected)
    }

    func testDetectSourceLayout_SingleCandidate() {
        let detected = LayoutMapper.detectSourceLayout(
            text: "hello",
            candidateLayouts: ["com.apple.keylayout.US"]
        )
        XCTAssertEqual(detected, "com.apple.keylayout.US")
    }

    func testDetectSourceLayout_NoCandidates() {
        let detected = LayoutMapper.detectSourceLayout(
            text: "hello",
            candidateLayouts: []
        )
        XCTAssertNil(detected)
    }

    func testDetectSourceLayout_OnlyNumbers() {
        let detected = LayoutMapper.detectSourceLayout(
            text: "12345",
            candidateLayouts: ["com.apple.keylayout.US", "com.apple.keylayout.Russian"]
        )
        // Numbers exist in both layouts — should pick one with higher score
        XCTAssertNotNil(detected)
    }

    // MARK: - Large Dataset: EN→RU word pairs

    func testConvertENtoRU_largeDataset() {
        let pairs: [(input: String, expected: String)] = [
            ("ghbdtn", "привет"),
            ("rfr ltkf", "как дела"),
            ("lheu", "друг"),
            ("vbh", "мир"),
            ("cjkywt", "солнце"),
            ("rjvgm.nth", "компьютер"),
            ("ghjuhfvvf", "программа"),
            ("ntrcn", "текст"),
            ("rkfdbfnehf", "клавиатура"),
            ("hf,jnf", "работа"),
            ("ljv", "дом"),
            ("xfq", "чай"),
            ("rjit", "коше"),  // кошe through mapping
            ("cjj,otybt", "сообщение"),
            ("cnhjrf", "строка"),
            (",erdf", "буква"),
            ("zyfrjvsq", "янакомый"),  // 'z' maps to 'я' on Russian keyboard, not 'з'
            ("cghfdjxybr", "справочник"),
        ]

        for pair in pairs {
            let result = LayoutMapper.convert(
                text: pair.input,
                from: "com.apple.keylayout.US",
                to: "com.apple.keylayout.Russian"
            )
            XCTAssertEqual(
                result, pair.expected,
                "Failed: '\(pair.input)' should convert to '\(pair.expected)', got '\(result ?? "nil")'")
        }
    }

    // MARK: - Large Dataset: RU→EN word pairs

    func testConvertRUtoEN_largeDataset() {
        let pairs: [(input: String, expected: String)] = [
            ("руддщ", "hello"),
            ("цщкдв", "world"),
            ("еуыештп", "testing"),  // 'г' (at 'g' key) not 'е' (at 't' key)
            ("зкщпкфь", "program"),
            ("ьфсщы", "macos"),
            ("ызусшфд", "special"),
            ("лунищфкв", "keyboard"),
            ("дфнщге", "layout"),
            ("ыцшеср", "switch"),
            ("сщтмуке", "convert"),
        ]

        for pair in pairs {
            let result = LayoutMapper.convert(
                text: pair.input,
                from: "com.apple.keylayout.Russian",
                to: "com.apple.keylayout.US"
            )
            XCTAssertEqual(
                result, pair.expected,
                "Failed: '\(pair.input)' should convert to '\(pair.expected)', got '\(result ?? "nil")'")
        }
    }

    // MARK: - Special characters and symbols

    func testConvertSpecialChars_brackets() {
        // '[' in US QWERTY → 'х' in Russian
        let result = LayoutMapper.convert(
            text: "[",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "х")
    }

    func testConvertSpecialChars_semicolon() {
        // ';' in US QWERTY → 'ж' in Russian
        let result = LayoutMapper.convert(
            text: ";",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "ж")
    }

    func testConvertSpecialChars_apostrophe() {
        // '\'' in US QWERTY → 'э' in Russian
        let result = LayoutMapper.convert(
            text: "'",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "э")
    }

    func testConvertSpecialChars_backtick() {
        // '`' in US QWERTY → 'ё' in Russian (non-letter → letter = converts)
        let result = LayoutMapper.convert(
            text: "`",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "ё")
    }

    // MARK: - Punctuation
    // Punctuation inside or at the end of a word converts by physical key like letters.
    // Standalone punctuation (a token without letters) is preserved as-is.

    func testPunctuationInWord_questionMarkBecomesComma() {
        // '?' (Shift+/) in QWERTY is ',' in Russian on the same physical key
        let result = LayoutMapper.convert(
            text: "ghbdtn?",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "привет,")
    }

    func testPunctuationInWord_sentence() {
        let result = LayoutMapper.convert(
            text: "ghbdtn? rfr ltkf&",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "привет, как дела?")
    }

    func testPunctuationInWord_reverse() {
        let result = LayoutMapper.convert(
            text: "руддщб цщкдв",
            from: "com.apple.keylayout.Russian",
            to: "com.apple.keylayout.US"
        )
        XCTAssertEqual(result, "hello, world")
    }

    func testPunctuationStandaloneToken_preserved() {
        let result = LayoutMapper.convert(
            text: "ghbdtn ? rfr",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "привет ? как")
    }

    func testPunctuationPreserved_questionMarkAlone() {
        let result = LayoutMapper.convert(
            text: "?",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "?")
    }

    func testPunctuationPreserved_exclamationMark() {
        // '!' (Shift+1) in QWERTY maps to '!' in Russian (same) — both non-letter → preserve
        let result = LayoutMapper.convert(
            text: "ghbdtn!",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "привет!")
    }

    func testPunctuationPreserved_slash() {
        // '/' in QWERTY maps to '.' in Russian — both non-letter → preserve '/'
        let result = LayoutMapper.convert(
            text: "/",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "/")
    }

    func testPunctuationStillConverts_semicolonToLetter() {
        // ';' → 'ж' (non-letter → letter) — must still convert
        let result = LayoutMapper.convert(
            text: ";",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "ж")
    }

    func testPunctuationStillConverts_commaToLetter() {
        // ',' → 'б' (non-letter → letter) — must still convert
        let result = LayoutMapper.convert(
            text: ",",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "б")
    }

    func testPunctuationStillConverts_dotToLetter() {
        // '.' → 'ю' (non-letter → letter) — must still convert
        let result = LayoutMapper.convert(
            text: ".",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "ю")
    }

    func testPunctuationInWord_fullPhrase() {
        // '?' ends the word "ltkf?", so it converts by physical key: "дела,"
        let result = LayoutMapper.convert(
            text: "ghbdtn rfr ltkf?",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "привет как дела,")
    }

    func testPunctuationPreserved_numbersUnchanged() {
        // Numbers are non-letter → non-letter, so they stay as-is (same as before)
        let result = LayoutMapper.convert(
            text: "123",
            from: "com.apple.keylayout.US",
            to: "com.apple.keylayout.Russian"
        )
        XCTAssertEqual(result, "123")
    }

    // MARK: - TargetLayoutResolver (priority order + script)

    private let us = "com.apple.keylayout.US"
    private let de = "com.apple.keylayout.German"
    private let ru = "com.apple.keylayout.Russian"
    private let uk = "com.apple.keylayout.Ukrainian"

    func testTarget_EnglishGoesToFirstCyrillicByPriority() {
        let order = [ru, uk, us, de]
        XCTAssertEqual(TargetLayoutResolver.targetID(forSource: us, ordered: order), ru)
    }

    func testTarget_GermanGoesToRussian() {
        let order = [ru, uk, us, de]
        XCTAssertEqual(TargetLayoutResolver.targetID(forSource: de, ordered: order), ru)
    }

    func testTarget_RussianGoesToFirstLatin() {
        let order = [ru, uk, us, de]
        XCTAssertEqual(TargetLayoutResolver.targetID(forSource: ru, ordered: order), us)
    }

    func testTarget_UkrainianGoesToFirstLatin() {
        let order = [ru, uk, us, de]
        XCTAssertEqual(TargetLayoutResolver.targetID(forSource: uk, ordered: order), us)
    }

    func testTarget_OrderMatters_UkrainianFirst() {
        let order = [uk, ru, us, de]
        XCTAssertEqual(TargetLayoutResolver.targetID(forSource: us, ordered: order), uk)
    }

    func testTarget_DisabledLayoutIsNotChosen() {
        // Russian disabled = absent from the ordered (enabled) list
        let order = [uk, us, de]
        XCTAssertEqual(TargetLayoutResolver.targetID(forSource: us, ordered: order), uk)
    }

    func testTarget_ExplicitOverrideWins() {
        let order = [ru, uk, us, de]
        XCTAssertEqual(
            TargetLayoutResolver.targetID(forSource: de, ordered: order, overrides: [de: uk]),
            uk
        )
    }

    func testTarget_OverrideToDisabledLayoutIsIgnored() {
        let order = [ru, us, de]
        XCTAssertEqual(
            TargetLayoutResolver.targetID(forSource: de, ordered: order, overrides: [de: uk]),
            ru
        )
    }

    func testTarget_SameScriptFallback() {
        let order = [us, de]
        XCTAssertEqual(TargetLayoutResolver.targetID(forSource: us, ordered: order), de)
    }

    func testTarget_RussianPCIsCyrillic() {
        let order = ["com.apple.keylayout.RussianWin", us]
        XCTAssertEqual(TargetLayoutResolver.targetID(forSource: us, ordered: order), "com.apple.keylayout.RussianWin")
    }
}

// MARK: - Pattern order

extension LayoutMapperTests {
    func testCharacterMapPatternOrder() {
        let cases: [(String, [Character: Character])] = [
            ("com.apple.keylayout.Russian", LayoutCharacterMap.russian),
            ("com.apple.keylayout.RussianWin", LayoutCharacterMap.russian),
            ("com.apple.keylayout.Ukrainian-PC", LayoutCharacterMap.ukrainian),
            ("com.apple.keylayout.German", LayoutCharacterMap.german),
            ("com.apple.keylayout.French", LayoutCharacterMap.french),
            ("com.apple.keylayout.Spanish", LayoutCharacterMap.spanish),
            ("com.apple.keylayout.British", LayoutCharacterMap.qwertyUS),
            ("com.apple.keylayout.ABC", LayoutCharacterMap.qwertyUS),
            ("com.apple.keylayout.US", LayoutCharacterMap.qwertyUS),
        ]
        for (id, expected) in cases {
            XCTAssertEqual(LayoutCharacterMap.characterMap(for: id), expected, id)
        }
        XCTAssertNil(LayoutCharacterMap.characterMap(for: "com.example.Greek"))
    }

    func testAllMapsPutsRussianBeforeUS() throws {
        let patterns = LayoutCharacterMap.allMaps.map(\.pattern)
        let russian = try XCTUnwrap(patterns.firstIndex(of: "russian"))
        let us = try XCTUnwrap(patterns.firstIndex(of: "us"))
        XCTAssertLessThan(russian, us)
    }
}

// Tests run against the shared maps unless they inject a provider.
extension LayoutMapper {
    static func convert(text: String, from sourceLayoutID: String, to targetLayoutID: String) -> String? {
        convert(text: text, from: sourceLayoutID, to: targetLayoutID, mapProvider: LayoutMaps.shared)
    }

    static func detectSourceLayout(text: String, candidateLayouts: [String]) -> String? {
        detectSourceLayout(text: text, candidateLayouts: candidateLayouts, mapProvider: LayoutMaps.shared)
    }
}

extension LayoutScript {
    static func of(layoutID: String) -> LayoutScript {
        of(layoutID: layoutID, mapProvider: LayoutMaps.shared)
    }
}

extension TargetLayoutResolver {
    static func targetID(forSource sourceID: String, ordered: [String], overrides: [String: String] = [:]) -> String? {
        targetID(forSource: sourceID, ordered: ordered, overrides: overrides, mapProvider: LayoutMaps.shared)
    }
}
