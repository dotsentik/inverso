import Foundation
import os

/// Unified logging, one category per area. Rules (checked by LoggingPolicyTests):
/// - user text (typed, selected, converted) only with `privacy: .private`;
/// - user text only at `.debug`, never at `.info` or above.
///
/// Read the logs: `log stream --level debug --predicate 'subsystem == "com.inverso.app"'`
enum Log {
    static let subsystem = "com.inverso.app"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let accessibility = Logger(subsystem: subsystem, category: "Accessibility")
    static let focus = Logger(subsystem: subsystem, category: "Focus")
    static let conversion = Logger(subsystem: subsystem, category: "Conversion")
    static let layouts = Logger(subsystem: subsystem, category: "Layouts")
    static let logStore = Logger(subsystem: subsystem, category: "LogStore")
}
