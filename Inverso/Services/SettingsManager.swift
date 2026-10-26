import SwiftUI

/// User preferences, persisted in UserDefaults.
@MainActor
final class SettingsManager: ObservableObject {

    /// Log size limit until the user changes it; also what turning "unlimited" off restores.
    static let defaultLogMaxEntries = SettingsKeys.Defaults.logMaxEntries

    private let defaults: UserDefaults

    // MARK: - Layouts

    /// All known layouts in the user's priority order (highest first), enabled and disabled.
    @Published var layoutOrder: [KeyboardLayout] {
        didSet { saveLayouts() }
    }

    /// Layouts the user switched off. They are ignored for detection and conversion.
    @Published var disabledLayoutIDs: Set<String> {
        didSet { defaults.set(Array(disabledLayoutIDs), forKey: SettingsKeys.disabledLayoutIDs) }
    }

    /// Explicit "source layout ID → target layout ID" choices. Missing key = automatic.
    @Published var targetOverrides: [String: String] {
        didSet { defaults.set(targetOverrides, forKey: SettingsKeys.targetOverrides) }
    }

    /// Enabled layouts in priority order. Used by the converter, detector and menu.
    var enabledLayouts: [KeyboardLayout] {
        get { layoutOrder.filter { !disabledLayoutIDs.contains($0.id) } }
        set {
            layoutOrder = newValue
            disabledLayoutIDs.subtract(newValue.map(\.id))
        }
    }

    // MARK: - Hotkey

    /// true = double Shift, false = the modifier + key shortcut below.
    @Published var useDoubleShift: Bool {
        didSet {
            defaults.set(useDoubleShift, forKey: SettingsKeys.useDoubleShift)
            NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
        }
    }

    @Published var hotkeyKeyCode: UInt16 {
        didSet {
            defaults.set(Int(hotkeyKeyCode), forKey: SettingsKeys.hotkeyKeyCode)
            if !useDoubleShift {
                NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
            }
        }
    }

    @Published var hotkeyModifiers: UInt {
        didSet {
            defaults.set(hotkeyModifiers, forKey: SettingsKeys.hotkeyModifiers)
            if !useDoubleShift {
                NotificationCenter.default.post(name: .hotkeySettingsChanged, object: nil)
            }
        }
    }

    var hotkeyModifierFlags: NSEvent.ModifierFlags {
        get { NSEvent.ModifierFlags(rawValue: hotkeyModifiers) }
        set { hotkeyModifiers = newValue.rawValue }
    }

    var hotkeyDescription: String {
        if useDoubleShift {
            return "⇧⇧ (Double Shift)"
        }
        return HotkeyManager.symbols(for: hotkeyModifierFlags) + HotkeyManager.keyName(for: hotkeyKeyCode)
    }

    // MARK: - Behavior

    @Published var conversionFeedback: ConversionFeedback {
        didSet { defaults.set(conversionFeedback.rawValue, forKey: SettingsKeys.conversionFeedback) }
    }

    @Published var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: SettingsKeys.playSounds) }
    }

    @Published var smartConversionMode: SmartConversionMode {
        didSet { defaults.set(smartConversionMode.rawValue, forKey: SettingsKeys.smartConversionMode) }
    }

    @Published var layoutSwitchMode: LayoutSwitchMode {
        didSet { defaults.set(layoutSwitchMode.rawValue, forKey: SettingsKeys.layoutSwitchMode) }
    }

    // MARK: - Statistics and Log

    @Published var conversionCount: Int {
        didSet { defaults.set(conversionCount, forKey: SettingsKeys.conversionCount) }
    }

    /// Off by default: the log stores the user's text.
    @Published var loggingEnabled: Bool {
        didSet { defaults.set(loggingEnabled, forKey: SettingsKeys.loggingEnabled) }
    }

    /// Max number of log entries to keep. 0 = unlimited.
    @Published var logMaxEntries: Int {
        didSet { defaults.set(logMaxEntries, forKey: SettingsKeys.logMaxEntries) }
    }

    // MARK: - Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        useDoubleShift =
            defaults.object(forKey: SettingsKeys.useDoubleShift) as? Bool
            ?? SettingsKeys.Defaults.useDoubleShift
        // Option+S, used when double Shift is off
        hotkeyKeyCode = UInt16(
            defaults.object(forKey: SettingsKeys.hotkeyKeyCode) as? Int
                ?? Int(SettingsKeys.Defaults.hotkeyKeyCode)
        )
        hotkeyModifiers =
            defaults.object(forKey: SettingsKeys.hotkeyModifiers) as? UInt
            ?? SettingsKeys.Defaults.hotkeyModifiers

        // The old "showNotifications" switch is not migrated: the HUD replaces per-conversion
        // notifications, which were the reason people turned them off.
        let savedFeedback = defaults.object(forKey: SettingsKeys.conversionFeedback) as? Int
        conversionFeedback =
            savedFeedback.flatMap(ConversionFeedback.init(rawValue:))
            ?? SettingsKeys.Defaults.conversionFeedback
        playSounds =
            defaults.object(forKey: SettingsKeys.playSounds) as? Bool
            ?? SettingsKeys.Defaults.playSounds
        let savedSmartMode = defaults.object(forKey: SettingsKeys.smartConversionMode) as? Int
        smartConversionMode =
            savedSmartMode.flatMap(SmartConversionMode.init(rawValue:))
            ?? SettingsKeys.Defaults.smartConversionMode
        let savedLayoutSwitchMode = defaults.object(forKey: SettingsKeys.layoutSwitchMode) as? Int
        layoutSwitchMode =
            savedLayoutSwitchMode.flatMap(LayoutSwitchMode.init(rawValue:))
            ?? SettingsKeys.Defaults.layoutSwitchMode

        conversionCount = defaults.integer(forKey: SettingsKeys.conversionCount)
        loggingEnabled =
            defaults.object(forKey: SettingsKeys.loggingEnabled) as? Bool
            ?? SettingsKeys.Defaults.loggingEnabled
        logMaxEntries =
            defaults.object(forKey: SettingsKeys.logMaxEntries) as? Int ?? Self.defaultLogMaxEntries

        if let data = defaults.data(forKey: SettingsKeys.enabledLayouts),
            let layouts = try? JSONDecoder().decode([KeyboardLayout].self, from: data),
            !layouts.isEmpty
        {
            layoutOrder = layouts
        } else {
            layoutOrder = KeyboardLayoutDetector.installedLayouts()
        }
        disabledLayoutIDs = Set(
            defaults.stringArray(forKey: SettingsKeys.disabledLayoutIDs)
                ?? Array(SettingsKeys.Defaults.disabledLayoutIDs)
        )
        targetOverrides =
            defaults.dictionary(forKey: SettingsKeys.targetOverrides) as? [String: String]
            ?? SettingsKeys.Defaults.targetOverrides

        // Pick up layouts added in System Settings since last launch, keeping the user's order
        refreshSystemLayouts()
    }

    // MARK: - Layout Management

    /// Syncs with the system input sources without losing the user's order and switches:
    /// layouts removed from the system disappear, new ones are appended at the end.
    func refreshSystemLayouts() {
        let installed = KeyboardLayoutDetector.installedLayouts()
        let installedIDs = Set(installed.map(\.id))
        var merged: [KeyboardLayout] = layoutOrder.compactMap { old in
            installed.first(where: { $0.id == old.id })
        }
        let known = Set(merged.map(\.id))
        merged += installed.filter { !known.contains($0.id) }
        if merged != layoutOrder {
            layoutOrder = merged
        }
        let keptDisabled = disabledLayoutIDs.intersection(installedIDs)
        if keptDisabled != disabledLayoutIDs {
            disabledLayoutIDs = keptDisabled
        }
        let keptOverrides = targetOverrides.filter { installedIDs.contains($0.key) && installedIDs.contains($0.value) }
        if keptOverrides != targetOverrides {
            targetOverrides = keptOverrides
        }
    }

    func moveLayouts(fromOffsets source: IndexSet, toOffset destination: Int) {
        layoutOrder.move(fromOffsets: source, toOffset: destination)
    }

    /// Moves one layout up (-1) or down (+1) in priority.
    func moveLayout(id: String, by delta: Int) {
        guard let index = layoutOrder.firstIndex(where: { $0.id == id }) else { return }
        let newIndex = index + delta
        guard layoutOrder.indices.contains(newIndex) else { return }
        layoutOrder.swapAt(index, newIndex)
    }

    func isLayoutEnabled(_ id: String) -> Bool {
        !disabledLayoutIDs.contains(id)
    }

    func setLayout(_ id: String, enabled: Bool) {
        if enabled {
            disabledLayoutIDs.remove(id)
        } else {
            disabledLayoutIDs.insert(id)
        }
    }

    /// nil target = automatic (by priority and script).
    func setTargetOverride(source: String, target: String?) {
        if let target, target != source {
            targetOverrides[source] = target
        } else {
            targetOverrides.removeValue(forKey: source)
        }
    }

    func incrementConversionCount() {
        conversionCount += 1
    }

    private func saveLayouts() {
        if let data = try? JSONEncoder().encode(layoutOrder) {
            defaults.set(data, forKey: SettingsKeys.enabledLayouts)
        }
    }
}

extension SettingsManager: ConversionPreferences {
    var enabledLayoutIDs: [String] { enabledLayouts.map(\.id) }
}
