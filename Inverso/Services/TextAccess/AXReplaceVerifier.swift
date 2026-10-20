import Foundation

/// Checks whether an AX write replaced the selection as expected.
enum AXReplaceVerifier {
    /// Compares the element's value after the write with what it should be.
    static func result(before: String, selectedRange: NSRange, inserted: String, after: String?) -> AXReplaceResult {
        guard let after else { return .unknown }
        let expected = (before as NSString).replacingCharacters(in: selectedRange, with: inserted)
        if after == expected { return .replaced }
        if after == before { return .unchanged }
        return .unknown
    }
}
