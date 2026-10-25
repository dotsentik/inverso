import Foundation

/// The 48 character keys that layout maps are keyed by: the 47 ANSI keys and the ISO section
/// key (left of 1 on ISO keyboards, where Russian – PC types ё).
enum PhysicalKeys {
    /// US-QWERTY characters of the keys: unshifted row, then shifted row. The section key is
    /// last in each row, as "§" and "±" (what ABC types on it).
    static let qwerty = Array(
        "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./§~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?±")

    /// Virtual key codes (HIToolbox Events.h) of the keys, in the order of the unshifted row of `qwerty`.
    static let keyCodes: [UInt16] = [
        0x32, 0x12, 0x13, 0x14, 0x15, 0x17, 0x16, 0x1A, 0x1C, 0x19, 0x1D, 0x1B, 0x18,
        0x0C, 0x0D, 0x0E, 0x0F, 0x11, 0x10, 0x20, 0x22, 0x1F, 0x23, 0x21, 0x1E, 0x2A,
        0x00, 0x01, 0x02, 0x03, 0x05, 0x04, 0x26, 0x28, 0x25, 0x29, 0x27,
        0x06, 0x07, 0x08, 0x09, 0x0B, 0x2D, 0x2E, 0x2B, 0x2F, 0x2C,
        0x0A,
    ]

    /// US-QWERTY characters of the section key.
    private static let isoKeys: Set<Character> = ["§", "±"]

    /// `qwerty` in the order a reverse lookup prefers keys: the ANSI keys (unshifted, then
    /// shifted) before the section key. A character the section key repeats (">" in
    /// Russian – Phonetic, ё in Russian – PC on ANSI keyboards) keeps its ANSI key.
    static let lookupOrder = qwerty.filter { !isoKeys.contains($0) } + qwerty.filter { isoKeys.contains($0) }
}
