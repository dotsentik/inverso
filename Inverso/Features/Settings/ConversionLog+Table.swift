import Foundation

/// Values the conversion log table shows and sorts by.
extension ConversionLog {
    /// "US → RussianWin": last component of each layout ID.
    var layoutsDescription: String {
        "\(Self.shortLayout(sourceLayout)) → \(Self.shortLayout(targetLayout))"
    }

    /// Sorts unrated, then correct, then incorrect.
    var ratingSortKey: Int {
        switch isCorrect {
        case nil: return 0
        case true?: return 1
        case false?: return 2
        }
    }

    /// Cycle: nil → true → false → nil.
    var nextRating: Bool? {
        switch isCorrect {
        case nil: return true
        case true?: return false
        case false?: return nil
        }
    }

    private static func shortLayout(_ layoutID: String) -> String {
        layoutID.split(separator: ".").last.map(String.init) ?? layoutID
    }
}
