import Foundation

/// Converts text between the enabled layouts: detects the layout the text was typed in and
/// converts it into the target layout; in a line, finds the part typed in the wrong layout.
@MainActor
final class TextConverter {

    /// Converted text with the layout it was detected in and the layout it was converted into.
    struct ConversionResult {
        /// The full replacement for the text passed in (for a line: kept part + converted part).
        let text: String
        let sourceLayoutID: String
        let targetLayoutID: String
        /// The part of the input that was converted; the whole input unless only a line's tail was.
        let originalSegment: String
        /// `originalSegment` after conversion.
        let convertedSegment: String
    }

    private let preferences: any ConversionPreferences
    private let mapProvider: any LayoutMapProviding
    private let currentLayoutIDProvider: () -> String?
    private let wordValidator: (any WordValidating)?

    /// - Parameter wordValidator: keeps correctly typed words before a line's wrong-layout tail;
    ///   without it only the script tells them apart.
    init(
        preferences: any ConversionPreferences,
        mapProvider: any LayoutMapProviding,
        currentLayoutID: @escaping () -> String?,
        wordValidator: (any WordValidating)? = nil
    ) {
        self.preferences = preferences
        self.mapProvider = mapProvider
        self.currentLayoutIDProvider = currentLayoutID
        self.wordValidator = wordValidator
    }

    // MARK: - Conversion

    /// Detects the layout `text` was typed in and converts it into the target layout.
    func convert(_ text: String) -> ConversionResult? {
        let layouts = preferences.enabledLayoutIDs
        Log.conversion.debug(
            "convert: enabledLayouts count=\(layouts.count), IDs=\(layouts, privacy: .public)")
        guard layouts.count >= 2 else {
            Log.conversion.debug("convert: fewer than 2 layouts, returning nil")
            return nil
        }

        guard
            let sourceID = LayoutMapper.detectSourceLayout(
                text: text,
                candidateLayouts: detectionCandidates(layouts),
                mapProvider: mapProvider
            )
        else {
            Log.conversion.debug("convert: detectSourceLayout returned nil")
            return nil
        }
        Log.conversion.debug("convert: detected source layout = '\(sourceID, privacy: .public)'")
        return convert(text, from: sourceID)
    }

    /// Converts `text` typed in `sourceID` into the target layout.
    private func convert(_ text: String, from sourceID: String) -> ConversionResult? {
        let layouts = preferences.enabledLayoutIDs
        guard
            let targetID = TargetLayoutResolver.targetID(
                forSource: sourceID,
                ordered: layouts,
                overrides: preferences.targetOverrides,
                mapProvider: mapProvider
            ),
            layouts.contains(targetID)
        else {
            Log.conversion.debug("convert: no target layout found different from source")
            return nil
        }

        Log.conversion.debug(
            "convert: converting from '\(sourceID, privacy: .public)' to '\(targetID, privacy: .public)'")
        guard
            let byKey = LayoutMapper.convert(
                text: text,
                from: sourceID,
                to: targetID,
                mapProvider: mapProvider
            )
        else { return nil }
        let result = restoringEdgePunctuation(original: text, converted: byKey, targetID: targetID)
        Log.conversion.debug("convert: result = '\(result, privacy: .private)'")
        // Digits, punctuation, emoji: nothing to write back, log or switch the layout for.
        guard result != text else {
            Log.conversion.debug("convert: result equals input, nothing to convert")
            return nil
        }
        return ConversionResult(
            text: result, sourceLayoutID: sourceID, targetLayoutID: targetID,
            originalSegment: text, convertedSegment: result)
    }

    /// Converts only the wrong-layout part of a line. Returns the whole replacement line
    /// (kept part + converted part), or nil if there is nothing to convert.
    func convertLineGreedily(_ text: String) -> ConversionResult? {
        guard let boundary = findWrongLayoutBoundary(in: text) else { return nil }
        // The tail's layout comes from the boundary: re-detecting it on the tail with its attached
        // punctuation could pick another layout.
        guard let converted = convert(boundary.convert, from: boundary.sourceLayoutID) else {
            Log.conversion.debug("convertLineGreedily: convert failed for '\(boundary.convert, privacy: .private)'")
            return nil
        }
        let result = boundary.keep + converted.text
        Log.conversion.debug("convertLineGreedily: '\(text, privacy: .private)' → '\(result, privacy: .private)'")
        return ConversionResult(
            text: result, sourceLayoutID: converted.sourceLayoutID, targetLayoutID: converted.targetLayoutID,
            originalSegment: boundary.convert, convertedSegment: converted.text)
    }

    // MARK: - Wrong Layout Detection

    /// True if the text switches script when converted, e.g. "ghbdtn" → "привет"
    /// or "руддщ" → "hello".
    func looksLikeWrongLayout(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            Log.conversion.debug("looksLikeWrongLayout: empty text")
            return false
        }

        let layouts = preferences.enabledLayoutIDs
        guard layouts.count >= 2 else {
            Log.conversion.debug("looksLikeWrongLayout: fewer than 2 layouts")
            return false
        }

        guard
            let sourceID = LayoutMapper.detectSourceLayout(
                text: trimmed,
                candidateLayouts: detectionCandidates(layouts),
                mapProvider: mapProvider
            )
        else {
            Log.conversion.debug("looksLikeWrongLayout: detectSourceLayout returned nil")
            return false
        }
        Log.conversion.debug(
            "looksLikeWrongLayout: detected source='\(sourceID, privacy: .public)' for '\(trimmed, privacy: .private)'")

        for layoutID in layouts where layoutID != sourceID {
            guard
                let converted = LayoutMapper.convert(
                    text: trimmed,
                    from: sourceID,
                    to: layoutID,
                    mapProvider: mapProvider
                )
            else { continue }
            Log.conversion.debug(
                "looksLikeWrongLayout: converted to '\(converted, privacy: .private)' via layout '\(layoutID, privacy: .public)'"
            )

            let sourceHasLatinOnly = trimmed.allSatisfy { $0.isASCII || !$0.isLetter }
            let convertedHasNonLatin = converted.contains { !$0.isASCII && $0.isLetter }
            let sourceHasNonLatin = trimmed.contains { !$0.isASCII && $0.isLetter }
            let convertedHasLatinOnly = converted.allSatisfy { $0.isASCII || !$0.isLetter }

            Log.conversion.debug(
                "looksLikeWrongLayout: srcLatinOnly=\(sourceHasLatinOnly) convNonLatin=\(convertedHasNonLatin) srcNonLatin=\(sourceHasNonLatin) convLatinOnly=\(convertedHasLatinOnly)"
            )

            if sourceHasLatinOnly && convertedHasNonLatin { return true }
            if sourceHasNonLatin && convertedHasLatinOnly { return true }
        }

        Log.conversion.debug("looksLikeWrongLayout: no wrong layout detected")
        return false
    }

    /// Splits a line (cursor to line start) into the part to keep and the wrong-layout part
    /// to convert. Returns nil if the end of the line does not look like the wrong layout.
    ///
    /// The wrong-layout part is the run of words at the end of the line typed in the same
    /// layout as the last word: "Привет, как дела? ntcn" converts only "ntcn", and
    /// "ghbdtn rfr ltkf lheu" converts as a whole. The run stops at the first word with a
    /// letter outside that layout, one that would not switch script, or (with a word
    /// validator) a correctly typed word: "Открой файл сщташп" converts only "сщташп". The last
    /// word always converts: the hotkey was pressed for it. Without a dictionary for the
    /// language a correct word of the same script as the tail converts with it.
    /// Digit-only tokens carry no layout signal and never stop the run;
    /// digits and spaces before the run's first word stay in keep. Punctuation attached to the
    /// first converted word ("2025 §krf") converts with it.
    func findWrongLayoutBoundary(in text: String) -> (keep: String, convert: String, sourceLayoutID: String)? {
        let layouts = preferences.enabledLayoutIDs
        guard layouts.count >= 2 else { return nil }

        let tokens = tokenize(text)
        guard let lastWord = tokens.last(where: { $0.containsLetter }) else { return nil }
        guard looksLikeWrongLayout(lastWord) else {
            Log.conversion.debug("findWrongLayoutBoundary: last word does not look like the wrong layout")
            return nil
        }
        guard
            let sourceID = LayoutMapper.detectSourceLayout(
                text: lastWord,
                candidateLayouts: detectionCandidates(layouts),
                mapProvider: mapProvider
            ),
            let sourceCharacters = mapProvider.characterSet(for: sourceID)
        else { return nil }
        Log.conversion.debug(
            "findWrongLayoutBoundary: \(tokens.count) tokens, tail layout '\(sourceID, privacy: .public)' in '\(text, privacy: .private)'"
        )

        let targetID = TargetLayoutResolver.targetID(
            forSource: sourceID, ordered: layouts, overrides: preferences.targetOverrides, mapProvider: mapProvider)
        let lastWordIndex = tokens.lastIndex { $0.containsLetter }

        // Right to left while the words are typed in the tail's layout.
        var wrongStartIndex = tokens.count
        for index in stride(from: tokens.count - 1, through: 0, by: -1) {
            let token = tokens[index]
            guard token.containsLetter else { continue }
            let isTypedInSource = token.allSatisfy { !$0.isLetter || sourceCharacters.contains($0) }
            let isCorrect =
                index != lastWordIndex && isCorrectlyTyped(token, sourceID: sourceID, targetID: targetID)
            guard isTypedInSource && !isCorrect && looksLikeWrongLayout(token) else {
                Log.conversion.debug(
                    "findWrongLayoutBoundary: token[\(index)] '\(token, privacy: .private)' stops the run")
                break
            }
            wrongStartIndex = index
        }
        guard wrongStartIndex < tokens.count else { return nil }

        var keep = tokens[..<wrongStartIndex].joined()
        var convert = tokens[wrongStartIndex...].joined()
        // Characters typed right before the word belong to it ("§krf" = "ёлка", ",f,eirf" =
        // "бабушка"); LayoutMapper keeps them as typed unless their key types a letter.
        let attached = keep.reversed().prefix { !$0.isWhitespace && !$0.isLetter && !$0.isNumber }
        if !attached.isEmpty {
            keep.removeLast(attached.count)
            convert = String(attached.reversed()) + convert
        }
        Log.conversion.debug(
            "findWrongLayoutBoundary: keep='\(keep, privacy: .private)' convert='\(convert, privacy: .private)'")

        return (keep: keep, convert: convert, sourceLayoutID: sourceID)
    }

    /// True if `word` is a real word of the source layout's language whose conversion is not a
    /// real word of the target's: "файл" (→ "afqk") is typed correctly. A word that is a real
    /// word both ways is ambiguous and does not count.
    private func isCorrectlyTyped(_ word: String, sourceID: String, targetID: String?) -> Bool {
        guard let wordValidator, !word.contains(where: \.isNumber),
            let sourceLanguage = preferences.languageCode(forLayoutID: sourceID),
            wordValidator.isWord(word, languageCode: sourceLanguage) == true
        else { return false }
        guard let targetID, let targetLanguage = preferences.languageCode(forLayoutID: targetID),
            let converted = LayoutMapper.convert(text: word, from: sourceID, to: targetID, mapProvider: mapProvider)
        else { return true }
        return wordValidator.isWord(converted, languageCode: targetLanguage) != true
    }

    // MARK: - Edge Punctuation

    /// Punctuation people type as punctuation in either layout. At a word's edge it stays as typed.
    private static let sentencePunctuation: Set<Character> = [
        ",", ".", "!", "?", ":", ";", "\"", "'", "«", "»", "„", "“", "”", "(", ")", "-", "–", "—", "…",
    ]

    /// LayoutMapper converts punctuation at a word's edges by key, so "ntcn," becomes "тестб" and
    /// "руддщ." becomes "hello/". For each whitespace-separated word, the sentence punctuation at
    /// its edges goes back to what was typed ("тест,", "hello."), unless the by-key word is a
    /// real word of the target language: "[kt," → "хлеб", "'nj" → "это", "pyf." → "знаю". When
    /// both are words, a trailing edge stays punctuation ("ntcn." → "тест.", not "тестю").
    /// Punctuation between letters ("k.,k." → "люблю") always converts by key.
    private func restoringEdgePunctuation(original: String, converted: String, targetID: String) -> String {
        let originalChars = Array(original)
        let convertedChars = Array(converted)
        // LayoutMapper maps one character to one and keeps whitespace, so the strings line up.
        guard originalChars.count == convertedChars.count else { return converted }
        let targetLanguage = preferences.languageCode(forLayoutID: targetID)

        var result = convertedChars
        var start = 0
        while start < originalChars.count {
            guard !originalChars[start].isWhitespace else {
                start += 1
                continue
            }
            var end = start
            while end < originalChars.count && !originalChars[end].isWhitespace { end += 1 }
            restoreEdges(of: start..<end, original: originalChars, into: &result, targetLanguage: targetLanguage)
            start = end
        }
        return String(result)
    }

    private func restoreEdges(
        of word: Range<Int>, original: [Character], into result: inout [Character], targetLanguage: String?
    ) {
        func isEdge(_ index: Int) -> Bool {
            !original[index].isLetter && Self.sentencePunctuation.contains(original[index])
        }
        var leading = word.lowerBound
        while leading < word.upperBound && isEdge(leading) { leading += 1 }
        var trailing = word.upperBound
        while trailing > leading && isEdge(trailing - 1) { trailing -= 1 }
        let edges = Array(word.lowerBound..<leading) + Array(trailing..<word.upperBound)
        // Nothing to restore if every edge character already came out as typed or as punctuation.
        guard edges.contains(where: { result[$0] != original[$0] && result[$0].isLetter }) else {
            for index in edges where result[index] != original[index] { result[index] = original[index] }
            return
        }
        var restored = result
        for index in edges { restored[index] = original[index] }
        if let targetLanguage, let wordValidator {
            func isWord(_ chars: ArraySlice<Character>) -> Bool {
                let core = String(chars).trimmingCharacters(in: .letters.inverted)
                return !core.isEmpty && wordValidator.isWord(core, languageCode: targetLanguage) == true
            }
            if isWord(result[word]) {
                // Both are words ("тестю" / "тест.", "это" / "'то"): punctuation is far more common at
                // a word's end, a letter at its start.
                let trailingBecameLetter = (trailing..<word.upperBound).contains { result[$0].isLetter }
                if !isWord(restored[word]) || !trailingBecameLetter { return }
            }
        }
        result = restored
    }

    // MARK: - Detection Order

    /// Candidate layout IDs for source detection: priority order, but the currently active
    /// system layout goes first. detectSourceLayout keeps the first layout on a tie, so
    /// U.S. vs German (or Russian vs Ukrainian) resolves to the layout actually used for typing.
    private func detectionCandidates(_ layouts: [String]) -> [String] {
        var ids = layouts
        if let currentID = currentLayoutIDProvider(),
            let index = ids.firstIndex(of: currentID), index != 0
        {
            ids.remove(at: index)
            ids.insert(currentID, at: 0)
        }
        return ids
    }

    // MARK: - Tokenization

    /// Splits text into words and runs of whitespace/punctuation. Joining the tokens gives
    /// back the original text exactly.
    private func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var inWord = false

        for char in text {
            let charIsWord = char.isLetter || char.isNumber
            if charIsWord != inWord && !current.isEmpty {
                tokens.append(current)
                current = ""
            }
            inWord = charIsWord
            current.append(char)
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}

extension String {
    /// True if the string has at least one letter.
    fileprivate var containsLetter: Bool {
        contains { $0.isLetter }
    }
}
