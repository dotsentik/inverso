import Foundation

/// Converts text between the enabled layouts: detects the layout the text was typed in and
/// converts it into the target layout; in a line, finds the part typed in the wrong layout.
@MainActor
final class TextConverter {

    /// Converted text and the layout it was converted into.
    struct ConversionResult {
        let text: String
        let targetLayoutID: String
    }

    /// A line converts as a whole when at least this share of its words switch script…
    private static let wholeLineWrongShare = 0.7
    /// …and it has at least this many words.
    private static let wholeLineMinimumWords = 3

    private let settingsManager: SettingsManager

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    // MARK: - Conversion

    /// Detects the layout `text` was typed in and converts it into the target layout.
    func convert(_ text: String) -> ConversionResult? {
        let layouts = settingsManager.enabledLayouts
        Log.conversion.debug(
            "convert: enabledLayouts count=\(layouts.count), IDs=\(layouts.map(\.id), privacy: .public)")
        guard layouts.count >= 2 else {
            Log.conversion.debug("convert: fewer than 2 layouts, returning nil")
            return nil
        }

        guard let sourceID = LayoutMapper.detectSourceLayout(text: text, candidateLayouts: detectionCandidates(layouts))
        else {
            Log.conversion.debug("convert: detectSourceLayout returned nil")
            return nil
        }
        Log.conversion.debug("convert: detected source layout = '\(sourceID, privacy: .public)'")

        guard let targetID = settingsManager.targetLayoutID(forSource: sourceID),
            let targetLayout = layouts.first(where: { $0.id == targetID })
        else {
            Log.conversion.debug("convert: no target layout found different from source")
            guard let firstLayout = layouts.first,
                let result = LayoutMapper.convert(text: text, from: sourceID, to: firstLayout.id)
            else { return nil }
            return ConversionResult(text: result, targetLayoutID: firstLayout.id)
        }

        Log.conversion.debug(
            "convert: converting from '\(sourceID, privacy: .public)' to '\(targetLayout.id, privacy: .public)'")
        let result = LayoutMapper.convert(text: text, from: sourceID, to: targetLayout.id)
        Log.conversion.debug("convert: result = '\(result ?? "nil", privacy: .private)'")
        return result.map { ConversionResult(text: $0, targetLayoutID: targetLayout.id) }
    }

    /// Converts only the wrong-layout part of a line. Returns the whole replacement line
    /// (kept part + converted part), or nil if there is nothing to convert.
    func convertLineGreedily(_ text: String) -> ConversionResult? {
        guard let boundary = findWrongLayoutBoundary(in: text) else { return nil }
        guard let converted = convert(boundary.convert) else {
            Log.conversion.debug("convertLineGreedily: convert failed for '\(boundary.convert, privacy: .private)'")
            return nil
        }
        let result = boundary.keep + converted.text
        Log.conversion.debug("convertLineGreedily: '\(text, privacy: .private)' → '\(result, privacy: .private)'")
        return ConversionResult(text: result, targetLayoutID: converted.targetLayoutID)
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

        let layouts = settingsManager.enabledLayouts
        guard layouts.count >= 2 else {
            Log.conversion.debug("looksLikeWrongLayout: fewer than 2 layouts")
            return false
        }

        guard
            let sourceID = LayoutMapper.detectSourceLayout(
                text: trimmed, candidateLayouts: detectionCandidates(layouts))
        else {
            Log.conversion.debug("looksLikeWrongLayout: detectSourceLayout returned nil")
            return false
        }
        Log.conversion.debug(
            "looksLikeWrongLayout: detected source='\(sourceID, privacy: .public)' for '\(trimmed, privacy: .private)'")

        for layout in layouts where layout.id != sourceID {
            guard let converted = LayoutMapper.convert(text: trimmed, from: sourceID, to: layout.id) else { continue }
            Log.conversion.debug(
                "looksLikeWrongLayout: converted to '\(converted, privacy: .private)' via layout '\(layout.id, privacy: .public)'"
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
    /// to convert. Returns nil if no part of the line looks like the wrong layout.
    ///
    /// Pass 1 checks the whole line: if all words (or most of a longer line) switch script,
    /// everything converts, as in "ghbdtn rfr ltkf lheu". Per-word gibberish scoring does not
    /// work here: many wrong-layout words ("lheu" = "друг") look like valid English.
    ///
    /// Pass 2 scans words right to left and stops at the first one that does not switch
    /// script, for mixed lines like "Привет ghbdtn rfr".
    func findWrongLayoutBoundary(in text: String) -> (keep: String, convert: String)? {
        guard settingsManager.enabledLayouts.count >= 2 else { return nil }

        let tokens = tokenize(text)
        let wordTokens = tokens.filter { !$0.isWhitespaceOrPunctuation }
        guard !wordTokens.isEmpty else { return nil }

        Log.conversion.debug(
            "findWrongLayoutBoundary: \(tokens.count) tokens (\(wordTokens.count) words) from '\(text, privacy: .private)'"
        )

        // Pass 1: the whole line
        let wrongCount = wordTokens.filter { looksLikeWrongLayout($0) }.count
        Log.conversion.debug("findWrongLayoutBoundary: \(wrongCount)/\(wordTokens.count) words look wrong-layout")

        if wrongCount == wordTokens.count {
            Log.conversion.debug("findWrongLayoutBoundary: ALL words are wrong-layout, converting entire line")
            return (keep: "", convert: text)
        }
        // One ambiguous word should not stop a longer line from converting
        if wordTokens.count >= Self.wholeLineMinimumWords
            && Double(wrongCount) / Double(wordTokens.count) >= Self.wholeLineWrongShare
        {
            Log.conversion.debug(
                "findWrongLayoutBoundary: \(wrongCount)/\(wordTokens.count) words wrong (>=70%), converting entire line"
            )
            return (keep: "", convert: text)
        }

        // Pass 2: right to left until the first word that does not switch script
        var wrongStartIndex = tokens.count
        for index in stride(from: tokens.count - 1, through: 0, by: -1) {
            let token = tokens[index]
            if token.isWhitespaceOrPunctuation { continue }
            if looksLikeWrongLayout(token) {
                wrongStartIndex = index
                Log.conversion.debug(
                    "findWrongLayoutBoundary: token[\(index)] '\(token, privacy: .private)' = wrong layout")
            } else {
                Log.conversion.debug(
                    "findWrongLayoutBoundary: token[\(index)] '\(token, privacy: .private)' = OK, stopping")
                break
            }
        }

        guard wrongStartIndex < tokens.count else {
            Log.conversion.debug("findWrongLayoutBoundary: no wrong-layout tokens found")
            return nil
        }

        let keep = tokens[..<wrongStartIndex].joined()
        let convert = tokens[wrongStartIndex...].joined()
        Log.conversion.debug(
            "findWrongLayoutBoundary: keep='\(keep, privacy: .private)' convert='\(convert, privacy: .private)'")

        guard !convert.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return (keep: keep, convert: convert)
    }

    // MARK: - Detection Order

    /// Candidate layout IDs for source detection: priority order, but the currently active
    /// system layout goes first. detectSourceLayout keeps the first layout on a tie, so
    /// U.S. vs German (or Russian vs Ukrainian) resolves to the layout actually used for typing.
    private func detectionCandidates(_ layouts: [KeyboardLayout]) -> [String] {
        var ids = layouts.map(\.id)
        if let currentID = KeyboardLayoutDetector.currentLayout()?.id,
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
    /// True if the string has no letters or digits.
    fileprivate var isWhitespaceOrPunctuation: Bool {
        allSatisfy { !$0.isLetter && !$0.isNumber }
    }
}
