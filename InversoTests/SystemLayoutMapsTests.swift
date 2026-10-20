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

    private func systemMap(
        _ id: String, file: StaticString = #filePath, line: UInt = #line
    ) throws -> [Character: Character] {
        let source = try XCTUnwrap(
            KeyboardLayoutDetector.keyboardLayoutSources(includeAllInstalled: true)
                .first { KeyboardLayoutDetector.sourceID(of: $0) == id },
            "\(id) is not installed", file: file, line: line
        )
        return try XCTUnwrap(SystemLayoutMapBuilder.characterMap(for: source), file: file, line: line)
    }

    private func letters(_ map: [Character: Character]) -> String {
        String("qwertyuiopasdfghjklzxcvbnm".map { map[$0] ?? "?" })
    }

    // MARK: - Physical keys

    func testPhysicalKeys_CoverTheTableKeys() throws {
        XCTAssertEqual(PhysicalKeys.qwerty.count, 94)
        XCTAssertEqual(PhysicalKeys.keyCodes.count, 47)
        XCTAssertEqual(Set(PhysicalKeys.keyCodes).count, 47, "key codes are unique")
        let usTable = try XCTUnwrap(LayoutCharacterMap.characterMap(for: "com.apple.keylayout.US"))
        XCTAssertEqual(Set(usTable.keys), Set(PhysicalKeys.qwerty))
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
