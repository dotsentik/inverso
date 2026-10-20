import Foundation

/// What the HUD shows after a conversion: "ghbdtn → привет · RU", or a short hint instead.
struct ConversionHUDContent: Equatable {
    let input: String
    let output: String
    /// Short code of the target layout, e.g. "RU".
    let layoutCode: String
    /// A hint shown instead of a conversion, e.g. why nothing was converted.
    let message: String?

    /// Longer text is cut in the middle so both ends stay readable.
    static let maxCharacters = 40

    init(input: String, output: String, layoutCode: String) {
        self.input = Self.shorten(input.trimmingCharacters(in: .whitespacesAndNewlines))
        self.output = Self.shorten(output.trimmingCharacters(in: .whitespacesAndNewlines))
        self.layoutCode = layoutCode
        message = nil
    }

    init(message: String) {
        input = ""
        output = ""
        layoutCode = ""
        self.message = message
    }

    /// Text for VoiceOver and the panel's accessibility label.
    var spokenText: String {
        message ?? "\(input) → \(output), \(layoutCode)"
    }

    /// Language code of the layout ("ru" → "RU"), or the last part of its ID.
    static func layoutCode(for layoutID: String?, in layouts: [KeyboardLayout]) -> String {
        guard let layoutID else { return "" }
        if let code = layouts.first(where: { $0.id == layoutID })?.languageCode, code != "unknown" {
            return code.split(separator: "-").first.map { $0.uppercased() } ?? code.uppercased()
        }
        return layoutID.split(separator: ".").last.map(String.init) ?? layoutID
    }

    static func shorten(_ text: String) -> String {
        guard text.count > maxCharacters else { return text }
        let kept = maxCharacters - 1  // One character goes to "…"
        let head = (kept + 1) / 2
        return "\(text.prefix(head))…\(text.suffix(kept - head))"
    }
}
