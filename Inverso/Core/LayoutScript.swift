import Foundation

/// Writing system of a layout. Used to pick a target layout of the *other* script
/// (Latin text → Cyrillic layout and vice versa) instead of just "the next one".
enum LayoutScript {
    case latin
    case cyrillic
    /// Any other script (Greek, Hebrew, Armenian, …), possible with layouts read from the system.
    case other

    /// Basic Latin … Latin Extended-B.
    private static let latinScalars: ClosedRange<UInt32> = 0x0041...0x024F
    /// Cyrillic + Cyrillic Supplement.
    private static let cyrillicScalars: ClosedRange<UInt32> = 0x0400...0x052F
    /// Unshifted letter keys of US-QWERTY.
    private static let letterKeys = "qwertyuiopasdfghjklzxcvbnm"

    static func of(
        layoutID: String,
        mapProvider: any LayoutMapProviding = LayoutMaps.shared
    ) -> LayoutScript {
        let lowered = layoutID.lowercased()
        if lowered.contains("russian") || lowered.contains("ukrainian") {
            return .cyrillic
        }
        if LayoutCharacterMap.characterMap(for: layoutID) != nil {
            return .latin
        }
        // Not in the tables: judge by the letters the system layout produces.
        return mapProvider.characterMap(for: layoutID).map { of(map: $0) } ?? .latin
    }

    /// Script of the majority of letters on the unshifted letter keys.
    static func of(map: [Character: Character]) -> LayoutScript {
        var counts: [LayoutScript: Int] = [:]
        for qwertyChar in letterKeys {
            guard let char = map[qwertyChar], char.isLetter, let scalar = char.unicodeScalars.first else { continue }
            switch scalar.value {
            case latinScalars: counts[.latin, default: 0] += 1
            case cyrillicScalars: counts[.cyrillic, default: 0] += 1
            default: counts[.other, default: 0] += 1
            }
        }
        return counts.max(by: { $0.value < $1.value })?.key ?? .latin
    }
}
