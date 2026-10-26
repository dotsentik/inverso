import Foundation

extension URL {
    /// Builds a URL from a string literal. The literal is part of the source, so an invalid one is a
    /// programming error: it traps instead of quietly falling back to a placeholder URL.
    init(staticString: StaticString) {
        guard let url = URL(string: staticString.description) else {
            preconditionFailure("Invalid URL literal: \(staticString)")
        }
        self = url
    }
}
