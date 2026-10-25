import Foundation
import ServiceManagement

/// Registers the app as a login item via SMAppService.mainApp. The system is the source
/// of truth: the toggle always reflects `SMAppService.status`.
@MainActor
final class LaunchAtLoginHelper: ObservableObject {

    @Published private(set) var status: SMAppService.Status
    /// Message of the last failed register/unregister; cleared on the next attempt.
    @Published private(set) var lastError: String?

    private let service: LoginItemService
    private let openLoginItemsSettings: () -> Void

    init(
        service: LoginItemService = SMAppService.mainApp,
        openLoginItemsSettings: @escaping () -> Void = { SMAppService.openSystemSettingsLoginItems() }
    ) {
        self.service = service
        self.openLoginItemsSettings = openLoginItemsSettings
        self.status = service.status
    }

    /// Checked only when the system will really launch the app at login.
    var isEnabled: Bool { status == .enabled }

    /// Registered, but the user has to allow it in System Settings → Login Items.
    var requiresApproval: Bool { status == .requiresApproval }

    /// Re-reads the status, e.g. after the user changed it in System Settings.
    func refresh() {
        status = service.status
    }

    func setEnabled(_ enabled: Bool) {
        lastError = nil
        if enabled && status == .requiresApproval {
            // register() would not change anything; only the user can approve.
            openLoginItemsSettings()
            return
        }
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            Log.app.info("Launch at login \(enabled ? "registered" : "unregistered", privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            Log.app.error(
                "Launch at login \(enabled ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        refresh()
        if status == .requiresApproval {
            Log.app.notice("Launch at login requires approval in System Settings")
        }
    }

    func openSystemSettings() {
        openLoginItemsSettings()
    }
}
