import Carbon
import Foundation

/// Builds character maps from the layouts installed in macOS (UCKeyTranslate over
/// kTISPropertyUnicodeKeyLayoutData). Same shape as the LayoutCharacterMap tables:
/// US-QWERTY character of a physical key → character the layout types on that key.
enum SystemLayoutMapBuilder {

    /// A layout that yields fewer characters is not a usable keyboard layout for conversion.
    static let minimumMappedKeys = 40

    /// UCKeyTranslate output buffer: one key never produces more UTF-16 units than this.
    private static let maxOutputLength = 4

    /// Map for an input source, or nil if it has no Unicode layout data (e.g. input methods).
    @MainActor
    static func characterMap(for source: TISInputSource) -> [Character: Character]? {
        guard let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return nil
        }
        let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
        return characterMap(layoutData: data, keyboardType: UInt32(LMGetKbdType()))
    }

    /// - Parameter layoutData: contents of kTISPropertyUnicodeKeyLayoutData ('uchr' resource).
    static func characterMap(layoutData: Data, keyboardType: UInt32) -> [Character: Character]? {
        layoutData.withUnsafeBytes { raw -> [Character: Character]? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var map: [Character: Character] = [:]
            let keyCount = PhysicalKeys.keyCodes.count
            for (index, qwertyChar) in PhysicalKeys.qwerty.enumerated() {
                let keyCode = PhysicalKeys.keyCodes[index % keyCount]
                if let char = translate(
                    layout, keyCode: keyCode, shifted: index >= keyCount, keyboardType: keyboardType)
                {
                    map[qwertyChar] = char
                }
            }
            return map.count >= minimumMappedKeys ? map : nil
        }
    }

    /// The single printable character the key produces, or nil.
    /// Dead keys return their own character (´, ^, ¨) instead of starting a sequence.
    private static func translate(
        _ layout: UnsafePointer<UCKeyboardLayout>,
        keyCode: UInt16,
        shifted: Bool,
        keyboardType: UInt32
    ) -> Character? {
        // UCKeyTranslate takes Carbon modifiers shifted right by 8: shiftKey (0x200) -> 0x02.
        let modifierState: UInt32 = shifted ? UInt32(shiftKey >> 8) & 0xFF : 0
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: maxOutputLength)
        let status = UCKeyTranslate(
            layout,
            keyCode,
            UInt16(kUCKeyActionDown),
            modifierState,
            keyboardType,
            OptionBits(kUCKeyTranslateNoDeadKeysMask),
            &deadKeyState,
            chars.count,
            &length,
            &chars
        )
        guard status == noErr, length > 0 else { return nil }
        let string = String(utf16CodeUnits: chars, count: length)
        guard string.count == 1, let char = string.first,
            !char.isWhitespace,
            char.unicodeScalars.allSatisfy({ $0.properties.generalCategory != .control })
        else { return nil }
        return char
    }
}
