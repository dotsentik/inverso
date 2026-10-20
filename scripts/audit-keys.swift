// Lists the keys that type a printable character in an installed keyboard layout but are
// missing from PhysicalKeys.keyCodes, for ANSI, ISO and JIS keyboards. Base and Shift layers
// only; the Option layer is not used for conversion.
//
// Usage: swift scripts/audit-keys.swift
// Output: tab-separated rows: layout ID, keyboard type, key code, without Shift, with Shift,
// and the mapped keys that type the same characters in that layout (- if none): such a key
// adds nothing a conversion could not already type.

import Carbon
import Foundation

/// Key codes of Inverso/Services/Layouts/PhysicalKeys.swift. Keep in sync.
let physicalKeyCodes: Set<Int> = [
    kVK_ANSI_Grave, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
    kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0, kVK_ANSI_Minus, kVK_ANSI_Equal,
    kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T, kVK_ANSI_Y, kVK_ANSI_U,
    kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket, kVK_ANSI_Backslash,
    kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_J,
    kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon, kVK_ANSI_Quote,
    kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M,
    kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_Slash,
    kVK_ISO_Section,
]

/// Modifiers, function and control keys, arrows and the keypad.
let skippedKeyCodes: Set<Int> = [
    kVK_Return, kVK_Tab, kVK_Space, kVK_Delete, kVK_Escape, kVK_ForwardDelete,
    kVK_Command, kVK_RightCommand, kVK_Shift, kVK_RightShift, kVK_CapsLock,
    kVK_Option, kVK_RightOption, kVK_Control, kVK_RightControl, kVK_Function,
    kVK_VolumeUp, kVK_VolumeDown, kVK_Mute, kVK_Help, kVK_Home, kVK_End, kVK_PageUp, kVK_PageDown,
    kVK_LeftArrow, kVK_RightArrow, kVK_DownArrow, kVK_UpArrow,
    kVK_F1, kVK_F2, kVK_F3, kVK_F4, kVK_F5, kVK_F6, kVK_F7, kVK_F8, kVK_F9, kVK_F10,
    kVK_F11, kVK_F12, kVK_F13, kVK_F14, kVK_F15, kVK_F16, kVK_F17, kVK_F18, kVK_F19, kVK_F20,
    kVK_ANSI_KeypadDecimal, kVK_ANSI_KeypadMultiply, kVK_ANSI_KeypadPlus, kVK_ANSI_KeypadClear,
    kVK_ANSI_KeypadDivide, kVK_ANSI_KeypadEnter, kVK_ANSI_KeypadMinus, kVK_ANSI_KeypadEquals,
    kVK_ANSI_Keypad0, kVK_ANSI_Keypad1, kVK_ANSI_Keypad2, kVK_ANSI_Keypad3, kVK_ANSI_Keypad4,
    kVK_ANSI_Keypad5, kVK_ANSI_Keypad6, kVK_ANSI_Keypad7, kVK_ANSI_Keypad8, kVK_ANSI_Keypad9,
    kVK_JIS_KeypadComma,
]

/// A hardware keyboard type of each physical layout, as LMGetKbdType reports it.
let keyboardTypes: [(name: String, type: UInt32, layoutType: Int)] = [
    ("ANSI", 40, kKeyboardANSI),
    ("ISO", 41, kKeyboardISO),
    ("JIS", 42, kKeyboardJIS),
]

/// The single printable character the key types, or nil (as SystemLayoutMapBuilder.translate).
func translate(_ layout: UnsafePointer<UCKeyboardLayout>, keyCode: UInt16, shifted: Bool, keyboardType: UInt32)
    -> Character?
{
    let modifierState: UInt32 = shifted ? UInt32(shiftKey >> 8) & 0xFF : 0
    var deadKeyState: UInt32 = 0
    var length = 0
    var chars = [UniChar](repeating: 0, count: 4)
    let status = UCKeyTranslate(
        layout, keyCode, UInt16(kUCKeyActionDown), modifierState, keyboardType,
        OptionBits(kUCKeyTranslateNoDeadKeysMask), &deadKeyState, chars.count, &length, &chars)
    guard status == noErr, length > 0 else { return nil }
    let string = String(utf16CodeUnits: chars, count: length)
    guard string.count == 1, let char = string.first, !char.isWhitespace,
        char.unicodeScalars.allSatisfy({ $0.properties.generalCategory != .control })
    else { return nil }
    return char
}

func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
    guard let pointer = TISGetInputSourceProperty(source, key) else { return nil }
    return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
}

for (name, type, layoutType) in keyboardTypes where KBGetLayoutType(Int16(type)) != layoutType {
    FileHandle.standardError.write("warning: keyboard type \(type) is not \(name)\n".data(using: .utf8)!)
}

let filter = [kTISPropertyInputSourceType as String: kTISTypeKeyboardLayout as String] as CFDictionary
let sources = (TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource]) ?? []

var rows: [String] = []
var layoutCount = 0
for source in sources {
    guard let id = stringProperty(source, kTISPropertyInputSourceID),
        let dataPointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
    else { continue }
    layoutCount += 1
    let data = Unmanaged<CFData>.fromOpaque(dataPointer).takeUnretainedValue() as Data
    data.withUnsafeBytes { raw in
        guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
        for (name, type, _) in keyboardTypes {
            var mappedKeys: [Character: Int] = [:]
            for keyCode in physicalKeyCodes.sorted() {
                for shifted in [false, true] {
                    if let char = translate(layout, keyCode: UInt16(keyCode), shifted: shifted, keyboardType: type),
                        mappedKeys[char] == nil
                    {
                        mappedKeys[char] = keyCode
                    }
                }
            }
            for keyCode in 0...0x7F where !physicalKeyCodes.contains(keyCode) && !skippedKeyCodes.contains(keyCode) {
                let plain = translate(layout, keyCode: UInt16(keyCode), shifted: false, keyboardType: type)
                let shifted = translate(layout, keyCode: UInt16(keyCode), shifted: true, keyboardType: type)
                guard plain != nil || shifted != nil else { continue }
                let elsewhere = [plain, shifted].compactMap { $0.flatMap { mappedKeys[$0] } }
                    .map { String(format: "0x%02X", $0) }
                rows.append(
                    [id, name, String(format: "0x%02X", keyCode), plain.map(String.init) ?? "-",
                        shifted.map(String.init) ?? "-", elsewhere.isEmpty ? "-" : elsewhere.joined(separator: ",")]
                        .joined(separator: "\t"))
            }
        }
    }
}

print("layout\tkeyboard\tkey\tplain\tshift\talso on")
rows.forEach { print($0) }
FileHandle.standardError.write("\(layoutCount) layouts with uchr data, \(rows.count) rows\n".data(using: .utf8)!)
