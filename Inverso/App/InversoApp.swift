import SwiftUI

@main
struct InversoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Menu bar app: no main window.
        MenuBarExtra {
            MenuBarContent(onConvert: { appDelegate.conversionCoordinator.convert() })
                .environmentObject(SettingsManager.shared)
                .environmentObject(LocalizationManager.shared)
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
                .environmentObject(SettingsManager.shared)
                .environmentObject(LocalizationManager.shared)
        }
        .windowResizability(.contentSize)
    }
}
