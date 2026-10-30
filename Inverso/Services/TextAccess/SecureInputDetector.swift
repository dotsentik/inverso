import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Tells whether the user is typing a secret. Then the hotkey must not select, copy or paste anything.
@MainActor
protocol SecureInputDetecting {
    func isSecureInputActive() -> Bool
}

/// Secure event input is on (password fields, secure keyboard entry) or the focused element
/// is a secure text field.
@MainActor
struct SecureInputDetector: SecureInputDetecting {
    func isSecureInputActive() -> Bool {
        IsSecureEventInputEnabled() || focusedElementIsSecureTextField()
    }

    private func focusedElementIsSecureTextField() -> Bool {
        var raw: CFTypeRef?
        var status = AXUIElementCopyAttributeValue(
            AXUIElementCreateSystemWide(), kAXFocusedUIElementAttribute as CFString, &raw)
        if status != .success, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
            status = AXUIElementCopyAttributeValue(
                AXUIElementCreateApplication(pid), kAXFocusedUIElementAttribute as CFString, &raw)
        }
        guard status == .success, let value = raw, CFGetTypeID(value) == AXUIElementGetTypeID() else { return false }
        let element = unsafeDowncast(value, to: AXUIElement.self)
        var subrole: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole) == .success
        else { return false }
        return (subrole as? String) == kAXSecureTextFieldSubrole as String
    }
}
