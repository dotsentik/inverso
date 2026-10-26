/// Picks the provider that shows the result of a conversion for the chosen feedback setting.
@MainActor
struct FeedbackProviders {
    private let hud: FeedbackProviding
    private let notification: FeedbackProviding
    private let silent: FeedbackProviding

    init(
        hud: FeedbackProviding,
        notification: FeedbackProviding = NotificationFeedbackProvider(),
        silent: FeedbackProviding = SilentFeedbackProvider()
    ) {
        self.hud = hud
        self.notification = notification
        self.silent = silent
    }

    func provider(for feedback: ConversionFeedback) -> FeedbackProviding {
        switch feedback {
        case .none: silent
        case .hud: hud
        case .notification: notification
        }
    }
}
