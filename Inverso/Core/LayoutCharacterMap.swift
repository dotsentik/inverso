import Foundation

/// Hardcoded character maps: US-QWERTY character of a physical key → character the layout
/// types on that key. The fallback when a layout's map cannot be read from the system,
/// and the deterministic source for tests.
enum LayoutCharacterMap {

    static let qwertyUS = table(String(PhysicalKeys.qwerty))

    /// Russian – PC: ё is on the key left of 1 (the grave key on ANSI keyboards, the section
    /// key on ISO ones).
    static let russian = table(
        "ё1234567890-=йцукенгшщзхъ\\фывапролджэячсмитьбю.ёЁ!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЪ/ФЫВАПРОЛДЖЭЯЧСМИТЬБЮ,Ё")

    /// QWERTZ.
    static let german = table(
        "^1234567890ß´qwertzuiopü+#asdfghjklöäyxcvbnm,.-°!\"§$%&/()=?`QWERTZUIOPÜ*'ASDFGHJKLÖÄYXCVBNM;:_")

    /// AZERTY.
    static let french = table(
        "²&é\"'(-è_çà)=azertyuiop^$*qsdfghjklmùwxcvbn,;:!³1234567890°+AZERTYUIOP¨£µQSDFGHJKLM%WXCVBN?./§")

    static let ukrainian = table(
        "'1234567890-=йцукенгшщзхї\\фівапролджєячсмитьбю.₴!\"№;%:?*()_+ЙЦУКЕНГШЩЗХЇ/ФІВАПРОЛДЖЄЯЧСМИТЬБЮ,")

    static let spanish = table(
        "º1234567890'¡qwertyuiop`+çasdfghjklñ´zxcvbnm,.-ª!\"·$%&/()=?¿QWERTYUIOP^*ÇASDFGHJKLÑ¨ZXCVBNM;:_")

    /// Layout ID patterns and their maps. Order matters: "russian" contains "us", so the
    /// specific patterns come first and "us" last. Do not reorder.
    static let allMaps: [(pattern: String, map: [Character: Character])] = [
        ("russian", russian),
        ("ukrainian", ukrainian),
        ("german", german),
        ("french", french),
        ("spanish", spanish),
        ("british", qwertyUS),  // Close enough for conversion
        ("abc", qwertyUS),
        ("us", qwertyUS),
    ]

    static func characterMap(for layoutID: String) -> [Character: Character]? {
        let lowered = layoutID.lowercased()
        for (pattern, map) in allMaps where lowered.contains(pattern) {
            Log.layouts.debug(
                "characterMap: '\(layoutID, privacy: .public)' matched pattern '\(pattern, privacy: .public)'")
            return map
        }
        Log.layouts.debug("characterMap: no match for '\(layoutID, privacy: .public)'")
        return nil
    }

    /// `layoutKeys` lists what the layout types on the keys of `PhysicalKeys.qwerty`, in order:
    /// unshifted row, then shifted row. A table may end its rows before the section key.
    private static func table(_ layoutKeys: String) -> [Character: Character] {
        let chars = Array(layoutKeys)
        let rowLength = chars.count / 2
        let keyCount = PhysicalKeys.keyCodes.count
        precondition(
            chars.count % 2 == 0 && rowLength <= keyCount, "rows of different length, or longer than PhysicalKeys")
        var map: [Character: Character] = [:]
        for index in 0..<rowLength {
            map[PhysicalKeys.qwerty[index]] = chars[index]
            map[PhysicalKeys.qwerty[keyCount + index]] = chars[rowLength + index]
        }
        return map
    }
}
