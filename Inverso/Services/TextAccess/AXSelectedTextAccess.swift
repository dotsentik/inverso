import AppKit
import ApplicationServices

/// Selection access through kAXSelectedTextAttribute. Many apps (Electron, some web views,
/// terminals) don't support it or claim success without changing anything, so every write
/// is verified and the caller falls back to ⌘C/⌘V when the text is provably unchanged.
@MainActor
struct AXSelectedTextAccess: SelectedTextAccess {

    /// Skip AX writes for huge values: verification reads the whole value twice.
    private static let maxVerifiableLength = 200_000
    /// Some apps apply the write asynchronously; re-check before declaring it unchanged.
    private static let verifyDelays: [Duration] = [.zero, .milliseconds(30), .milliseconds(70)]
    /// Seconds an AX call may take before it fails.
    private static let messagingTimeout: Float = 0.25

    private let systemWide: AXUIElement
    private var overlayPID: pid_t?

    init() {
        systemWide = AXUIElementCreateSystemWide()
        // Applies to all AX calls of this process: a hung app must not stall the main thread.
        AXUIElementSetMessagingTimeout(systemWide, Self.messagingTimeout)
    }

    func focused(onOverlay pid: pid_t?) -> SelectedTextAccess {
        var copy = self
        copy.overlayPID = pid
        return copy
    }

    func selectedText() -> String? {
        guard let element = focusedTextElement() else { return nil }
        guard let text: String = attribute(element, kAXSelectedTextAttribute), !text.isEmpty else {
            Log.accessibility.debug("AX: no selected text on focused element")
            return nil
        }
        Log.accessibility.debug("AX: selected text = '\(text, privacy: .private)'")
        return text
    }

    func selectedLength() -> Int? {
        guard let element = focusedTextElement() else {
            Log.accessibility.debug("AX: selectedLength: no focused element")
            return nil
        }
        guard let range = selectedRange(element), range.location != NSNotFound else {
            Log.accessibility.debug("AX: selectedLength: no selected range")
            return nil
        }
        Log.accessibility.debug("AX: selectedLength = \(range.length)")
        return range.length
    }

    func replaceSelectedText(with text: String) async -> AXReplaceResult {
        guard let element = focusedTextElement() else { return .unchanged }

        var settable: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success,
            settable.boolValue
        else {
            Log.accessibility.debug("AX: selected text is not settable")
            return .unchanged
        }
        guard let before: String = attribute(element, kAXValueAttribute),
            before.utf16.count <= Self.maxVerifiableLength,
            let range = selectedRange(element),
            range.location != NSNotFound, NSMaxRange(range) <= before.utf16.count
        else {
            Log.accessibility.debug("AX: value or selected range unavailable, cannot verify a write")
            return .unchanged
        }

        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
        Log.accessibility.debug("AX: set selected text status=\(status.rawValue)")

        var result = AXReplaceResult.unchanged
        for delay in Self.verifyDelays {
            if delay != .zero {
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    break
                }
            }
            let after: String? = attribute(element, kAXValueAttribute)
            result = AXReplaceVerifier.result(before: before, selectedRange: range, inserted: text, after: after)
            if result != .unchanged { break }
        }
        Log.accessibility.debug("AX: replace result = \(String(describing: result), privacy: .public)")
        return result
    }

    func textState() -> OverlayTextSelection.State? {
        guard let element = focusedTextElement() else { return nil }
        guard let value: String = attribute(element, kAXValueAttribute),
            value.utf16.count <= Self.maxVerifiableLength,
            let range = selectedRange(element), range.location != NSNotFound
        else {
            Log.focus.debug("AX: textState: value or selected range unavailable")
            return nil
        }
        Log.focus.debug("AX: textState: valueLength=\(value.utf16.count) range=\(range.location),\(range.length)")
        return OverlayTextSelection.State(value: value, selectedRange: range)
    }

    func setSelectedRange(_ range: NSRange) -> Bool {
        guard let element = focusedTextElement() else { return false }
        var settable: DarwinBoolean = false
        guard
            AXUIElementIsAttributeSettable(element, kAXSelectedTextRangeAttribute as CFString, &settable) == .success,
            settable.boolValue
        else {
            Log.focus.debug("AX: selected range is not settable")
            return false
        }
        var cfRange = CFRange(location: range.location, length: range.length)
        guard let value = AXValueCreate(.cfRange, &cfRange) else { return false }
        let status = AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, value)
        let after = selectedRange(element)
        Log.focus.debug(
            "AX: set selected range \(range.location),\(range.length) status=\(status.rawValue) now=\(after.map { "\($0.location),\($0.length)" } ?? "nil", privacy: .public)"
        )
        return status == .success && after == range
    }

    // MARK: - Helpers

    private func focusedTextElement() -> AXUIElement? {
        var raw: CFTypeRef?
        var status: AXError
        if let overlayPID {
            // Spotlight / Open-Save panel: the system-wide focus would be the app behind it.
            // Never fall back to that app: we would read or write the wrong text field.
            status = AXUIElementCopyAttributeValue(
                AXUIElementCreateApplication(overlayPID), kAXFocusedUIElementAttribute as CFString, &raw)
            Log.focus.debug("AX: overlay pid=\(overlayPID) has the focus, focused element error=\(status.rawValue)")
        } else {
            status = AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &raw)
        }
        if status != .success, overlayPID == nil, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            // The system-wide element sometimes fails with kAXErrorCannotComplete (seen with
            // Obsidian right after the hotkey); asking the frontmost app directly still works.
            let app = AXUIElementCreateApplication(pid)
            let appStatus = AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &raw)
            Log.accessibility.debug(
                "AX: system-wide focused element error=\(status.rawValue), frontmost app: \(appStatus.rawValue)")
            status = appStatus
        }
        // `as?` to a CF type is unchecked, so verify the type ID explicitly
        guard status == .success, let value: CFTypeRef = raw,
            CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        let role: String? = attribute(element, kAXRoleAttribute)
        let subrole: String? = attribute(element, kAXSubroleAttribute)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        Log.focus.debug(
            "AX: focused element pid=\(pid) app=\(NSRunningApplication(processIdentifier: pid)?.bundleIdentifier ?? "?", privacy: .public) role=\(role ?? "-", privacy: .public) subrole=\(subrole ?? "-", privacy: .public)"
        )
        if subrole == kAXSecureTextFieldSubrole as String {
            return nil
        }
        return element
    }

    private func selectedRange(_ element: AXUIElement) -> NSRange? {
        guard let raw: CFTypeRef = attribute(element, kAXSelectedTextRangeAttribute),
            CFGetTypeID(raw) == AXValueGetTypeID()
        else { return nil }
        let value = unsafeDowncast(raw, to: AXValue.self)
        var range = CFRange()
        guard AXValueGetValue(value, .cfRange, &range) else { return nil }
        return NSRange(location: range.location, length: range.length)
    }

    private func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success, let value else {
            return nil
        }
        return value as? T
    }
}
