import Carbon
import XCTest

@testable import Inverso

/// Character maps read from macOS layouts via UCKeyTranslate. Uses layouts that ship with
/// every macOS install (enabled or not), so the tests do not depend on the user's settings.
@MainActor
final class SystemLayoutMapsTests: XCTestCase {

    override func tearDown() async throws {
        LayoutMaps.useSystemLayouts = true
        LayoutMaps.reloadFromSystem()
        try await super.tearDown()
    }

    /// Hardware keyboard types (LMGetKbdType) of an ANSI and an ISO keyboard.
    private static let ansiKeyboard: UInt32 = 40
    private static let isoKeyboard: UInt32 = 41

    private func source(
        _ id: String, file: StaticString = #filePath, line: UInt = #line
    ) throws -> TISInputSource {
        try XCTUnwrap(
            KeyboardLayoutDetector.keyboardLayoutSources(includeAllInstalled: true)
                .first { KeyboardLayoutDetector.sourceID(of: $0) == id },
            "\(id) is not installed", file: file, line: line
        )
    }

    private func systemMap(
        _ id: String, file: StaticString = #filePath, line: UInt = #line
    ) throws -> [Character: Character] {
        try XCTUnwrap(
            SystemLayoutMapBuilder.characterMap(for: source(id, file: file, line: line)), file: file, line: line)
    }

    /// The map of a layout as macOS builds it for a keyboard of this type.
    private func systemMap(
        _ id: String, keyboardType: UInt32, file: StaticString = #filePath, line: UInt = #line
    ) throws -> [Character: Character] {
        let pointer = try XCTUnwrap(
            TISGetInputSourceProperty(try source(id, file: file, line: line), kTISPropertyUnicodeKeyLayoutData),
            file: file, line: line)
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return try XCTUnwrap(
            SystemLayoutMapBuilder.characterMap(layoutData: data, keyboardType: keyboardType), file: file, line: line)
    }

    private func letters(_ map: [Character: Character]) -> String {
        String("qwertyuiopasdfghjklzxcvbnm".map { map[$0] ?? "?" })
    }

    // MARK: - Physical keys

    func testPhysicalKeys_CoverTheTableKeys() throws {
        XCTAssertEqual(PhysicalKeys.qwerty.count, 96)
        XCTAssertEqual(PhysicalKeys.keyCodes.count, 48)
        XCTAssertEqual(Set(PhysicalKeys.keyCodes).count, 48, "key codes are unique")
        XCTAssertEqual(Set(PhysicalKeys.qwerty).count, 96, "QWERTY characters are unique")
        XCTAssertEqual(Set(PhysicalKeys.lookupOrder), Set(PhysicalKeys.qwerty))
        let usTable = try XCTUnwrap(LayoutCharacterMap.characterMap(for: "com.apple.keylayout.US"))
        XCTAssertEqual(Set(usTable.keys), Set(PhysicalKeys.qwerty))
    }

    func testPhysicalKeys_SectionKeyIsLastInBothRows() {
        let keyCount = PhysicalKeys.keyCodes.count
        XCTAssertEqual(PhysicalKeys.keyCodes.last, UInt16(kVK_ISO_Section))
        XCTAssertEqual(PhysicalKeys.qwerty[keyCount - 1], "§")
        XCTAssertEqual(PhysicalKeys.qwerty[2 * keyCount - 1], "±")
        XCTAssertEqual(PhysicalKeys.lookupOrder.suffix(2), ["§", "±"])
    }

    func testKeyboardTypes() {
        XCTAssertEqual(KBGetLayoutType(Int16(Self.ansiKeyboard)), UInt32(kKeyboardANSI))
        XCTAssertEqual(KBGetLayoutType(Int16(Self.isoKeyboard)), UInt32(kKeyboardISO))
    }

    // MARK: - Tables without the section key

    func testTablesWithoutSectionKey() {
        for table in [
            LayoutCharacterMap.german, LayoutCharacterMap.french, LayoutCharacterMap.ukrainian,
            LayoutCharacterMap.spanish,
        ] {
            XCTAssertEqual(table.count, 94)
            XCTAssertNil(table["§"])
            XCTAssertNil(table["±"])
        }
        XCTAssertEqual(LayoutCharacterMap.german["`"], "^")
        XCTAssertEqual(LayoutCharacterMap.german["~"], "°")
        XCTAssertEqual(LayoutCharacterMap.german["/"], "-")
        XCTAssertEqual(LayoutCharacterMap.german["?"], "_")
    }

    func testRussianTable_HasYoOnBothKeys() {
        XCTAssertEqual(LayoutCharacterMap.russian.count, 96)
        XCTAssertEqual(LayoutCharacterMap.russian["`"], "ё")
        XCTAssertEqual(LayoutCharacterMap.russian["§"], "ё")
        XCTAssertEqual(LayoutCharacterMap.russian["~"], "Ё")
        XCTAssertEqual(LayoutCharacterMap.russian["±"], "Ё")
        XCTAssertEqual(LayoutCharacterMap.russian["?"], ",")
        XCTAssertEqual(LayoutMapper.reverseMap(LayoutCharacterMap.russian)["ё"], "`", "the ANSI key wins")
    }

    func testTablesOnly_SectionKeyWithoutTableEntryStaysAsTyped() {
        LayoutMaps.useSystemLayouts = false
        XCTAssertEqual(
            LayoutMapper.convert(text: "§ ±", from: "com.apple.keylayout.US", to: "com.apple.keylayout.German"), "§ ±")
        XCTAssertEqual(
            LayoutMapper.convert(text: "§krf", from: "com.apple.keylayout.US", to: "com.apple.keylayout.Russian"),
            "ёлка")
    }

    // MARK: - UCKeyTranslate

    func testSystemUS_IsIdentityOnLettersAndDigits() throws {
        let map = try systemMap("com.apple.keylayout.US")
        for char in "qwertyuiopasdfghjklzxcvbnmQWERTYUIOPASDFGHJKLZXCVBNM1234567890" {
            XCTAssertEqual(map[char], char)
        }
        XCTAssertEqual(map["!"], "!")
        XCTAssertEqual(map[","], ",")
    }

    func testSystemRussian_Letters() throws {
        let map = try systemMap("com.apple.keylayout.Russian")
        XCTAssertEqual(letters(map), "йцукенгшщзфывапролдячсмить")
        XCTAssertEqual(map["Q"], "Й")
        XCTAssertEqual(map[";"], "ж")
        XCTAssertEqual(map["."], "ю")
    }

    func testSystemRussianPC_MatchesTableOnLetterKeys() throws {
        let map = try systemMap("com.apple.keylayout.RussianWin")
        let table = try XCTUnwrap(LayoutCharacterMap.characterMap(for: "com.apple.keylayout.RussianWin"))
        for char in "qwertyuiop[]asdfghjkl;'zxcvbnm,.`" {
            XCTAssertEqual(map[char], table[char], "key '\(char)'")
        }
    }

    func testSystemUkrainianPC_HasUkrainianLetters() throws {
        let map = try systemMap("com.apple.keylayout.Ukrainian-PC")
        XCTAssertEqual(map["s"], "і")
        XCTAssertEqual(map["]"], "ї")
        XCTAssertEqual(map["'"], "є")
    }

    func testSystemGerman_QWERTZAndDeadKey() throws {
        let map = try systemMap("com.apple.keylayout.German")
        XCTAssertEqual(map["y"], "z")
        XCTAssertEqual(map["z"], "y")
        XCTAssertEqual(map[";"], "ö")
        XCTAssertEqual(map["="], "´", "dead key yields its own character")
    }

    func testEmptyLayoutData_ReturnsNil() {
        XCTAssertNil(SystemLayoutMapBuilder.characterMap(layoutData: Data(), keyboardType: UInt32(LMGetKbdType())))
    }

    func testConvertWithSystemMaps() throws {
        LayoutMaps.setSystemMaps([
            "com.apple.keylayout.US": try systemMap("com.apple.keylayout.US"),
            "com.apple.keylayout.RussianWin": try systemMap("com.apple.keylayout.RussianWin"),
        ])

        XCTAssertEqual(
            LayoutMapper.convert(text: "ghbdtn", from: "com.apple.keylayout.US", to: "com.apple.keylayout.RussianWin"),
            "привет")
        XCTAssertEqual(
            LayoutMapper.convert(text: "руддщ", from: "com.apple.keylayout.RussianWin", to: "com.apple.keylayout.US"),
            "hello")
    }

    // MARK: - ISO keyboards

    func testISO_SectionKeyTypesYoInRussianPC() throws {
        let russian = try systemMap("com.apple.keylayout.RussianWin", keyboardType: Self.isoKeyboard)
        let abc = try systemMap("com.apple.keylayout.ABC", keyboardType: Self.isoKeyboard)
        let us = try systemMap("com.apple.keylayout.US", keyboardType: Self.isoKeyboard)

        XCTAssertEqual(russian["§"], "ё")
        XCTAssertEqual(russian["±"], "Ё")
        XCTAssertEqual(abc["§"], "§")
        XCTAssertEqual(abc["±"], "±")
        XCTAssertEqual(us["§"], "§")
        XCTAssertEqual(us["±"], "±")
        XCTAssertEqual(LayoutMapper.reverseMap(russian)["ё"], "§")
        XCTAssertEqual(LayoutMapper.reverseMap(russian)["Ё"], "±")
        XCTAssertEqual(letters(russian), "йцукенгшщзфывапролдячсмить")
    }

    func testANSI_YoStaysOnGraveKey() throws {
        let russian = try systemMap("com.apple.keylayout.RussianWin", keyboardType: Self.ansiKeyboard)
        let abc = try systemMap("com.apple.keylayout.ABC", keyboardType: Self.ansiKeyboard)

        XCTAssertEqual(russian["`"], "ё")
        XCTAssertEqual(abc["`"], "`")
        XCTAssertEqual(abc["~"], "~")
        XCTAssertEqual(LayoutMapper.reverseMap(russian)["ё"], "`", "the ANSI key wins over the section key")
    }

    func testSectionKeyDoesNotTakeOverShiftedCharacters() throws {
        // Russian – Phonetic types ">" on the section key and on Shift+".".
        let phonetic = try systemMap("com.apple.keylayout.Russian-Phonetic", keyboardType: Self.isoKeyboard)
        XCTAssertEqual(phonetic["§"], ">")
        XCTAssertEqual(LayoutMapper.reverseMap(phonetic)[">"], ">")
    }

    /// U.S. and Russian – PC maps for an ISO keyboard, stored under the IDs of the enabled
    /// U.S.-like and Russian layouts. Returns their IDs.
    private func useISOMaps() throws -> (latin: String, russian: String) {
        let ids = SettingsManager().enabledLayouts.map(\.id)
        let latin = try XCTUnwrap(ids.first { LayoutCharacterMap.characterMap(for: $0) == LayoutCharacterMap.qwertyUS })
        let russian = try XCTUnwrap(
            ids.first { LayoutCharacterMap.characterMap(for: $0) == LayoutCharacterMap.russian })
        LayoutMaps.setSystemMaps([
            latin: try systemMap("com.apple.keylayout.US", keyboardType: Self.isoKeyboard),
            russian: try systemMap("com.apple.keylayout.RussianWin", keyboardType: Self.isoKeyboard),
        ])
        return (latin, russian)
    }

    func testISO_ConvertSectionKeyWords() throws {
        let (latin, russian) = try useISOMaps()

        XCTAssertEqual(LayoutMapper.convert(text: "§krf", from: latin, to: russian), "ёлка")
        XCTAssertEqual(LayoutMapper.convert(text: "±KRF", from: latin, to: russian), "ЁЛКА")
        XCTAssertEqual(LayoutMapper.convert(text: "ёлка", from: russian, to: latin), "§krf")
        XCTAssertEqual(LayoutMapper.convert(text: "ЁЛКА", from: russian, to: latin), "±KRF")
        XCTAssertEqual(LayoutMapper.convert(text: "Привет §krf", from: latin, to: russian), "Привет ёлка")
        XCTAssertEqual(LayoutMapper.convert(text: "Hello ёлка", from: russian, to: latin), "Hello §krf")
    }

    func testISO_TextConverter() throws {
        _ = try useISOMaps()
        let converter = TextConverter(settingsManager: SettingsManager())

        XCTAssertEqual(converter.convert("§krf")?.text, "ёлка")
        XCTAssertEqual(converter.convert("±KRF")?.text, "ЁЛКА")
        XCTAssertEqual(converter.convert("ёлка")?.text, "§krf")
        XCTAssertEqual(converter.convert("ЁЛКА")?.text, "±KRF")
        XCTAssertEqual(converter.convert("ghbdtn §krf")?.text, "привет ёлка")
        XCTAssertEqual(converter.convert("ghbdtn §krf!")?.text, "привет ёлка!")
        XCTAssertEqual(converter.convert("ёлка и ёж")?.text, "§krf b §;")
        XCTAssertEqual(converter.convertLineGreedily("§krf")?.text, "ёлка")
        XCTAssertEqual(converter.convertLineGreedily("ghbdtn §krf")?.text, "привет ёлка")
        XCTAssertEqual(converter.convertLineGreedily("2025 §krf")?.text, "2025 ёлка")
        XCTAssertEqual(converter.convertLineGreedily("2025 ёлка")?.text, "2025 §krf")
    }

    // MARK: - LayoutMaps

    private static let greekLike: [Character: Character] = {
        var map: [Character: Character] = [:]
        for (qwerty, greek) in zip("qwertyuiopasdfghjklzxcvbnm", ";ςερτυθιοπασδφγηξκλζχψωβνμ") {
            map[qwerty] = greek
        }
        return map
    }()

    func testSystemMapIsPreferredOverTable() {
        let custom: [Character: Character] = ["q": "x"]
        LayoutMaps.setSystemMaps(["com.apple.keylayout.US": custom])

        XCTAssertEqual(LayoutMaps.characterMap(for: "com.apple.keylayout.US"), custom)
    }

    func testTableIsFallbackWhenSystemHasNoMap() {
        LayoutMaps.setSystemMaps([:])

        XCTAssertEqual(LayoutMaps.characterMap(for: "com.apple.keylayout.US"), LayoutCharacterMap.qwertyUS)
    }

    func testTablesOnlyMode_IgnoresSystemMaps() {
        LayoutMaps.setSystemMaps(["com.example.Greek": Self.greekLike])
        LayoutMaps.useSystemLayouts = false

        XCTAssertNil(LayoutMaps.characterMap(for: "com.example.Greek"))
    }

    func testLayoutUnknownToTables_WorksThroughSystemMap() {
        LayoutMaps.setSystemMaps(["com.example.Greek": Self.greekLike])

        XCTAssertEqual(
            LayoutMapper.convert(text: "kalh", from: "com.apple.keylayout.US", to: "com.example.Greek"), "καλη")
    }

    // MARK: - Script of system-only layouts

    func testScriptFromMap() {
        XCTAssertEqual(LayoutScript.of(map: Self.greekLike), .other)
        XCTAssertEqual(LayoutScript.of(map: LayoutCharacterMap.russian), .cyrillic)
        XCTAssertEqual(LayoutScript.of(map: LayoutCharacterMap.german), .latin)
    }

    func testTargetForOtherScriptLayout() {
        LayoutMaps.setSystemMaps(["com.example.Greek": Self.greekLike])

        XCTAssertEqual(LayoutScript.of(layoutID: "com.example.Greek"), .other)
        XCTAssertEqual(
            TargetLayoutResolver.targetID(
                forSource: "com.apple.keylayout.US",
                ordered: ["com.apple.keylayout.US", "com.apple.keylayout.German", "com.example.Greek"]),
            "com.example.Greek"
        )
    }

    // MARK: - Reverse map

    func testReverseMap_PrefersUnshiftedKey() {
        // "." on both the unshifted "/" key and shifted "?" key, like some system layouts.
        let map: [Character: Character] = ["/": ".", "?": "."]
        XCTAssertEqual(LayoutMapper.reverseMap(map)["."], "/")
    }
}
