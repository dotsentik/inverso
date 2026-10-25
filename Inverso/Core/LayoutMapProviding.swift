import Foundation

/// Provides forward and reverse character maps and character sets for keyboard layouts.
protocol LayoutMapProviding: Sendable {
    func characterMap(for layoutID: String) -> [Character: Character]?
    func reverseMap(for layoutID: String) -> [Character: Character]?
    func characterSet(for layoutID: String) -> Set<Character>?
}

extension LayoutMapProviding {
    func reverseMap(for layoutID: String) -> [Character: Character]? {
        characterMap(for: layoutID).map(LayoutMapper.reverseMap)
    }

    func characterSet(for layoutID: String) -> Set<Character>? {
        characterMap(for: layoutID).map { Set($0.values) }
    }
}
