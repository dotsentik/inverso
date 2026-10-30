import Foundation

/// Facts about the process the app runs in.
enum AppEnvironment {
    /// True when the app is the host of a test run. Then it must not trigger system prompts
    /// (Accessibility) or start background services (updates).
    static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }
}
