import Foundation

/// Tracks the selected keyboard input source for the checkmark in the menu.
@MainActor
final class InputSourceMonitor: ObservableObject {
    static let shared = InputSourceMonitor()

    @Published private(set) var currentLayoutID: String?

    /// Value of kTISNotifySelectedKeyboardInputSourceChanged (the C global is not concurrency-safe).
    private static let selectedSourceChanged = Notification.Name(
        "com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged")

    private init() {
        currentLayoutID = KeyboardLayoutDetector.currentLayout()?.id
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(selectedSourceDidChange),
            name: Self.selectedSourceChanged,
            object: nil
        )
    }

    @objc private func selectedSourceDidChange() {
        currentLayoutID = KeyboardLayoutDetector.currentLayout()?.id
    }
}
