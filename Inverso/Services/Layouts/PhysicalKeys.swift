import Carbon

/// The 48 character keys that layout maps are keyed by: the 47 ANSI keys and the ISO section
/// key (left of 1 on ISO keyboards, where Russian – PC types ё).
enum PhysicalKeys {
    /// US-QWERTY characters of the keys: unshifted row, then shifted row. The section key is
    /// last in each row, as "§" and "±" (what ABC types on it).
    static let qwerty = Array(
        "`1234567890-=qwertyuiop[]\\asdfghjkl;'zxcvbnm,./§~!@#$%^&*()_+QWERTYUIOP{}|ASDFGHJKL:\"ZXCVBNM<>?±")

    /// Virtual key codes of the keys, in the order of the unshifted row of `qwerty`.
    static let keyCodes: [UInt16] = [
        kVK_ANSI_Grave, kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5, kVK_ANSI_6,
        kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9, kVK_ANSI_0, kVK_ANSI_Minus, kVK_ANSI_Equal,
        kVK_ANSI_Q, kVK_ANSI_W, kVK_ANSI_E, kVK_ANSI_R, kVK_ANSI_T, kVK_ANSI_Y, kVK_ANSI_U,
        kVK_ANSI_I, kVK_ANSI_O, kVK_ANSI_P, kVK_ANSI_LeftBracket, kVK_ANSI_RightBracket, kVK_ANSI_Backslash,
        kVK_ANSI_A, kVK_ANSI_S, kVK_ANSI_D, kVK_ANSI_F, kVK_ANSI_G, kVK_ANSI_H, kVK_ANSI_J,
        kVK_ANSI_K, kVK_ANSI_L, kVK_ANSI_Semicolon, kVK_ANSI_Quote,
        kVK_ANSI_Z, kVK_ANSI_X, kVK_ANSI_C, kVK_ANSI_V, kVK_ANSI_B, kVK_ANSI_N, kVK_ANSI_M,
        kVK_ANSI_Comma, kVK_ANSI_Period, kVK_ANSI_Slash,
        kVK_ISO_Section,
    ].map { UInt16($0) }

    /// US-QWERTY characters of the section key.
    private static let isoKeys: Set<Character> = ["§", "±"]

    /// `qwerty` in the order a reverse lookup prefers keys: the ANSI keys (unshifted, then
    /// shifted) before the section key. A character the section key repeats (">" in
    /// Russian – Phonetic, ё in Russian – PC on ANSI keyboards) keeps its ANSI key.
    static let lookupOrder = qwerty.filter { !isoKeys.contains($0) } + qwerty.filter { isoKeys.contains($0) }
}
