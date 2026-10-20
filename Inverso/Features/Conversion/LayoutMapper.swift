import Foundation

/// Maps text from one keyboard layout to another through physical key positions.
enum LayoutMapper {

    /// Converts text typed in one layout to what the same keys type in another.
    ///
    /// Inside a word (from its first letter to the next whitespace) punctuation converts by
    /// physical key like letters: "ghbdtn?" → "привет,", "ltkf&" → "дела?". Standalone
    /// punctuation (a token without letters) and punctuation before a word's first letter
    /// stay as typed. A key that types a letter in either layout counts as a letter:
    /// ";" → "ж", ",f,eirf" → "бабушка".
    static func convert(text: String, from sourceLayoutID: String, to targetLayoutID: String) -> String? {
        guard let sourceMap = LayoutMaps.characterMap(for: sourceLayoutID) else {
            Log.conversion.error(
                "LayoutMapper.convert: no characterMap for source '\(sourceLayoutID, privacy: .public)'")
            return nil
        }
        guard let targetMap = LayoutMaps.characterMap(for: targetLayoutID) else {
            Log.conversion.error(
                "LayoutMapper.convert: no characterMap for target '\(targetLayoutID, privacy: .public)'")
            return nil
        }

        // Maps are keyed by the US-QWERTY character of a key; the reverse map finds the key
        // that typed a character in the source layout.
        let reverseSource = reverseMap(sourceMap)

        var result = ""
        var unmappedCount = 0
        var inWord = false
        for char in text {
            if char.isWhitespace {
                inWord = false
            } else if char.isLetter {
                inWord = true
            }
            if let physicalKey = reverseSource[char], let targetChar = targetMap[physicalKey] {
                if targetChar.isLetter {
                    inWord = true
                }
                if !inWord && !char.isLetter && !targetChar.isLetter {
                    result.append(char)
                } else {
                    result.append(targetChar)
                }
            } else {
                // Not on any key of the layout: spaces, emoji, characters of other layouts
                result.append(char)
                if char.isLetter {
                    unmappedCount += 1
                }
            }
        }

        Log.conversion.debug(
            "LayoutMapper.convert: '\(text, privacy: .private)' -> '\(result, privacy: .private)' (unmappedLetters=\(unmappedCount))"
        )
        return result
    }

    /// Layout character → US-QWERTY character of its key. If a character sits on several keys
    /// (common in system layouts), the first in QWERTY order wins, so unshifted keys are preferred.
    static func reverseMap(_ map: [Character: Character]) -> [Character: Character] {
        var reverse: [Character: Character] = [:]
        for qwertyChar in PhysicalKeys.qwerty {
            if let layoutChar = map[qwertyChar], reverse[layoutChar] == nil {
                reverse[layoutChar] = qwertyChar
            }
        }
        return reverse
    }

    /// The candidate whose character set contains most characters of `text`.
    /// On a tie the earlier candidate wins.
    static func detectSourceLayout(text: String, candidateLayouts: [String]) -> String? {
        var bestMatch: String?
        var bestScore = 0

        for layoutID in candidateLayouts {
            guard let map = LayoutMaps.characterMap(for: layoutID) else {
                Log.conversion.debug("detectSourceLayout: no characterMap for '\(layoutID, privacy: .public)'")
                continue
            }
            let layoutChars = Set(map.values)
            let score = text.filter { layoutChars.contains($0) }.count
            Log.conversion.debug(
                "detectSourceLayout: layout '\(layoutID, privacy: .public)' score=\(score) for '\(text, privacy: .private)'"
            )
            if score > bestScore {
                bestScore = score
                bestMatch = layoutID
            }
        }

        Log.conversion.debug(
            "detectSourceLayout: best match = '\(bestMatch ?? "nil", privacy: .public)' (score=\(bestScore))")
        return bestMatch
    }
}
