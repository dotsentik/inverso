import SwiftUI

@main
struct InversoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu bar app: no main window.
        MenuBarExtra {
            MenuBarContent(
                inputSource: appDelegate.inputSourceMonitor,
                updates: appDelegate.updateController,
                onConvert: { appDelegate.conversionCoordinator.convert() }
            )
            .environmentObject(appDelegate.settingsManager)
            .environmentObject(appDelegate.l10n)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(
                logStore: appDelegate.conversionLogStore,
                launchAtLogin: appDelegate.launchAtLoginHelper,
                updates: appDelegate.updateController
            )
            .environmentObject(appDelegate.settingsManager)
            .environmentObject(appDelegate.l10n)
        }
        .windowResizability(.contentSize)
    }
}
