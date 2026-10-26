import AppKit
import SwiftUI

/// Status item icon. Also hosts the bridge that opens the Settings scene on request
/// from AppKit code (openSettings exists only inside SwiftUI views).
struct MenuBarLabel: View {
    private static let icon = makeIcon()

    static func makeIcon() -> NSImage {
        let image: NSImage
        if let custom = NSImage(named: "MenuBarIcon") {
            image = custom
        } else {
            image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Inverso") ?? NSImage()
        }
        image.isTemplate = true
        image.size = NSSize(width: 18, height: 18)
        image.accessibilityDescription = "Inverso"
        return image
    }

    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(nsImage: Self.icon)
            .accessibilityLabel("Inverso")
            .onReceive(NotificationCenter.default.publisher(for: .openSettingsRequest)) { _ in
                NSApp.activate()
                openSettings()
            }
    }
}
