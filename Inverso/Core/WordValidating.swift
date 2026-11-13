import Foundation

/// Tells whether a word is a correctly spelled word of a language. Lets the greedy line
/// conversion keep correctly typed words that precede the wrong-layout tail.
@MainActor
protocol WordValidating: AnyObject {
    /// True if `word` is a word of `languageCode` ("en", "ru"…); nil if there is no dictionary
    /// for that language, so the caller cannot tell.
    func isWord(_ word: String, languageCode: String) -> Bool?
}
