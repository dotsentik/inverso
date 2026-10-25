import AppKit
import SwiftUI

/// A small non-activating panel at the top of the screen that shows the last conversion.
/// Never takes focus or mouse events, so typing continues in the frontmost app.
@MainActor
final class ConversionHUD: FeedbackProviding {

    static let shared = ConversionHUD()

    /// How long the HUD stays fully visible.
    var displayDuration: Duration = .milliseconds(1000)
    /// Forces a background style instead of following the system (tests, screenshots).
    var backgroundOverride: HUDBackgroundStyle?

    private(set) var panel: NSPanel?
    private(set) var hostingView: NSHostingView<ConversionHUDView>?
    private var hideTask: Task<Void, Never>?

    private static let topMargin: CGFloat = 8
    private static let slideDistance: CGFloat = 8
    private static let fadeInDuration: TimeInterval = 0.18
    private static let fadeOutDuration: TimeInterval = 0.25

    func showConversion(input: String, output: String, layoutCode: String) {
        show(ConversionHUDContent(input: input, output: output, layoutCode: layoutCode))
    }

    func showMessage(_ message: String) {
        show(ConversionHUDContent(message: message))
    }

    func show(_ content: ConversionHUDContent) {
        let workspace = NSWorkspace.shared
        let reduceMotion = workspace.accessibilityDisplayShouldReduceMotion
        let background =
            backgroundOverride
            ?? HUDBackgroundStyle.current(reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency)

        let rootView = ConversionHUDView(content: content, background: background)
        let panel: NSPanel
        let hosting: NSHostingView<ConversionHUDView>
        if let existingPanel = self.panel, let existingHosting = self.hostingView {
            panel = existingPanel
            hosting = existingHosting
            hosting.rootView = rootView
        } else {
            let newPanel = self.panel ?? makePanel()
            let newHosting = NSHostingView(rootView: rootView)
            newPanel.contentView = newHosting
            self.panel = newPanel
            self.hostingView = newHosting
            panel = newPanel
            hosting = newHosting
        }
        let finalFrame = Self.frame(size: hosting.fittingSize, on: Self.screenWithMouse())

        hideTask?.cancel()
        panel.setAccessibilityLabel(content.spokenText)

        if panel.isVisible && panel.alphaValue > 0 {
            // Already on screen: just swap the text, no second entrance animation
            panel.setFrame(finalFrame, display: true)
            panel.alphaValue = 1
        } else {
            let startFrame = reduceMotion ? finalFrame : finalFrame.offsetBy(dx: 0, dy: Self.slideDistance)
            panel.setFrame(startFrame, display: false)
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.fadeInDuration
                panel.animator().alphaValue = 1
                if !reduceMotion { panel.animator().setFrame(finalFrame, display: true) }
            }
        }

        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: content.spokenText, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )

        hideTask = Task { [weak self, displayDuration] in
            try? await Task.sleep(for: displayDuration)
            guard !Task.isCancelled else { return }
            self?.hide()
        }
    }

    func hide() {
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.fadeOutDuration
            panel.animator().alphaValue = 0
        } completionHandler: { [weak panel] in
            Task { @MainActor in
                if let panel, panel.alphaValue == 0 { panel.orderOut(nil) }
            }
        }
    }

    // MARK: - Panel

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false  // Drawn by the SwiftUI background
        panel.isReleasedWhenClosed = false
        panel.setAccessibilityRole(.popover)
        return panel
    }

    /// Centered horizontally, just below the menu bar of `screen`.
    static func frame(size: NSSize, on screen: NSScreen?) -> NSRect {
        guard let visible = screen?.visibleFrame else {
            return NSRect(origin: .zero, size: size)
        }
        return NSRect(
            x: visible.midX - size.width / 2,
            y: visible.maxY - size.height - topMargin,
            width: size.width,
            height: size.height
        ).integral
    }

    private static func screenWithMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }
}
