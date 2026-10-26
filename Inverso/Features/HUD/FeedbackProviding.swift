import AppKit
import UserNotifications

/// Provides user-visible or audible feedback when a layout conversion finishes or a status hint is shown.
@MainActor
protocol FeedbackProviding {
    func showConversion(input: String, output: String, layoutCode: String)
    func showMessage(_ message: String)
}

extension FeedbackProviding {
    func showMessage(_ message: String) {}
}

/// Displays conversion results and status hints in the non-activating top-of-screen HUD panel.
@MainActor
final class HUDFeedbackProvider: FeedbackProviding {
    private let hudBuilder: @MainActor () -> ConversionHUD
    private var cachedHUD: ConversionHUD?

    var hud: ConversionHUD {
        if let cachedHUD {
            return cachedHUD
        }
        let instance = hudBuilder()
        cachedHUD = instance
        return instance
    }

    init(hud: @autoclosure @escaping @MainActor () -> ConversionHUD = ConversionHUD()) {
        self.hudBuilder = hud
    }

    func showConversion(input: String, output: String, layoutCode: String) {
        hud.show(ConversionHUDContent(input: input, output: output, layoutCode: layoutCode))
    }

    func showMessage(_ message: String) {
        hud.show(ConversionHUDContent(message: message))
    }
}

/// Posts a macOS user notification for completed conversions.
@MainActor
struct NotificationFeedbackProvider: FeedbackProviding {
    private let sendNotification: @MainActor (String, String) -> Void

    init(
        sendNotification: @escaping @MainActor (String, String) -> Void = { input, output in
            Self.postSystemNotification(input: input, output: output)
        }
    ) {
        self.sendNotification = sendNotification
    }

    func showConversion(input: String, output: String, layoutCode: String) {
        sendNotification(input, output)
    }

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private static func postSystemNotification(input: String, output: String) {
        let content = UNMutableNotificationContent()
        content.title = "Inverso"
        content.body = "\(input) → \(output)"
        content.sound = nil

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                Log.app.error("Failed to show notification: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

/// No-op feedback provider used when visual or audible feedback is disabled.
@MainActor
struct SilentFeedbackProvider: FeedbackProviding {
    func showConversion(input: String, output: String, layoutCode: String) {}
}
