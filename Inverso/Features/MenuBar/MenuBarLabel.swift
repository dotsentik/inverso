import SwiftUI

/// Status item icon. Also hosts the bridge that opens the Settings scene on request
/// from AppKit code (openSettings exists only inside SwiftUI views).
struct MenuBarLabel: View {
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: "keyboard")
            .accessibilityLabel("Inverso")
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                NSApp.activate()
                openSettings()
            }
    }
}
