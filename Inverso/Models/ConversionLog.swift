import Foundation

/// One conversion stored in the conversion log, for review and labeling.
struct ConversionLog: Identifiable {
    let id: Int64
    let timestamp: Date
    let inputText: String
    let outputText: String
    /// Layout ID, e.g. "com.apple.keylayout.US".
    let sourceLayout: String
    let targetLayout: String
    /// "direct", "lastWord" or "greedyLine".
    let conversionMode: String
    /// nil = unrated, true = correct, false = incorrect.
    var isCorrect: Bool?
}
