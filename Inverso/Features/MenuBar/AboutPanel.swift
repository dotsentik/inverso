import AppKit

/// Options of the standard About panel. Name, version and copyright come from Info.plist.
/// Only the short version is shown ("Version 1.2.7"): it already contains the build number.
enum AboutPanel {
    /// The project this app is forked from, and its license.
    static let originalProjectURL = URL(string: "https://github.com/reg2005/langSwitcher")!
    static let originalLicenseURL = URL(string: "https://github.com/reg2005/langSwitcher/blob/main/LICENSE")!

    @MainActor
    static func options(l10n: LocalizationManager) -> [NSApplication.AboutPanelOptionKey: Any] {
        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
        let credits = NSMutableAttributedString(
            string: l10n.localized("about.tagline") + "\n",
            attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]
        )
        credits.append(
            NSAttributedString(
                string: l10n.localized("about.basedOn") + "\n", attributes: [.link: originalProjectURL, .font: font]))
        credits.append(
            NSAttributedString(
                string: l10n.localized("about.fork"),
                attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
        credits.append(
            NSAttributedString(string: " · ", attributes: [.foregroundColor: NSColor.secondaryLabelColor, .font: font]))
        credits.append(
            NSAttributedString(
                string: l10n.localized("about.license"), attributes: [.link: originalLicenseURL, .font: font]))
        let centered = NSMutableParagraphStyle()
        centered.alignment = .center
        credits.addAttribute(.paragraphStyle, value: centered, range: NSRange(location: 0, length: credits.length))
        // An empty build version hides the "(6)" after the version
        return [.credits: credits, .version: ""]
    }
}
