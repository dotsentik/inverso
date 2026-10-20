import SwiftUI

/// Layout priority, on/off switches and explicit target layouts.
struct LayoutsSettingsTab: View {
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var l10n: LocalizationManager
    @State private var selection: String?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    ForEach(Array(settingsManager.layoutOrder.enumerated()), id: \.element.id) { index, layout in
                        LayoutRow(layout: layout, priority: index + 1)
                            .tag(layout.id)
                    }
                    .onMove { source, destination in
                        settingsManager.moveLayouts(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    HStack {
                        Text(l10n.localized("layouts.title"))
                        Spacer()
                        Text(l10n.localized("layouts.convertTo"))
                            .frame(width: LayoutRow.targetPickerWidth, alignment: .leading)
                    }
                }
            }
            .listStyle(.inset)
            .frame(maxHeight: .infinity)
            // Keyboard: Space switches the selected layout on or off
            .onKeyPress(.space) {
                guard let selection else { return .ignored }
                settingsManager.setLayout(selection, enabled: !settingsManager.isLayoutEnabled(selection))
                return .handled
            }

            Text(l10n.localized("layouts.dragHint"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

            Divider()

            HStack {
                Button(l10n.localized("layouts.refresh")) {
                    settingsManager.refreshSystemLayouts()
                }

                Text(
                    l10n.localized("layouts.count").replacingOccurrences(
                        of: "%d", with: "\(settingsManager.enabledLayouts.count)")
                )
                .foregroundStyle(.secondary)

                Spacer()

                ControlGroup {
                    Button {
                        moveSelection(by: -1)
                    } label: {
                        Label(l10n.localized("layouts.moveUp"), systemImage: "chevron.up")
                    }
                    .keyboardShortcut(.upArrow, modifiers: [.command, .option])
                    .disabled(!canMoveSelection(by: -1))
                    .help(l10n.localized("layouts.moveUp"))

                    Button {
                        moveSelection(by: 1)
                    } label: {
                        Label(l10n.localized("layouts.moveDown"), systemImage: "chevron.down")
                    }
                    .keyboardShortcut(.downArrow, modifiers: [.command, .option])
                    .disabled(!canMoveSelection(by: 1))
                    .help(l10n.localized("layouts.moveDown"))
                }
                .labelStyle(.iconOnly)
                .fixedSize()
            }
            .padding(12)
        }
        .settingsTabFrame()
    }

    private func canMoveSelection(by delta: Int) -> Bool {
        guard let selection, let index = settingsManager.layoutOrder.firstIndex(where: { $0.id == selection }) else {
            return false
        }
        return settingsManager.layoutOrder.indices.contains(index + delta)
    }

    private func moveSelection(by delta: Int) {
        guard let selection else { return }
        settingsManager.moveLayout(id: selection, by: delta)
    }
}

private struct LayoutRow: View {
    static let targetPickerWidth: CGFloat = 150

    let layout: KeyboardLayout
    let priority: Int
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var l10n: LocalizationManager

    var body: some View {
        let enabled = settingsManager.isLayoutEnabled(layout.id)
        HStack(spacing: 10) {
            Text(priority, format: .number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(minWidth: 16, alignment: .trailing)
                .accessibilityHidden(true)

            Toggle(
                isOn: Binding(
                    get: { settingsManager.isLayoutEnabled(layout.id) },
                    set: { settingsManager.setLayout(layout.id, enabled: $0) }
                )
            ) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(layout.localizedName)
                    Text(layout.id)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .toggleStyle(.checkbox)
            .help(l10n.localized("layouts.enabled.help"))
            // Name + priority; the checked state stays the toggle's own value
            .accessibilityLabel(
                "\(layout.localizedName), \(l10n.localized("layouts.priority").replacingOccurrences(of: "%d", with: "\(priority)"))"
            )

            Spacer(minLength: 8)

            Picker(
                l10n.localized("layouts.convertTo"),
                selection: Binding<String>(
                    get: { settingsManager.targetOverrides[layout.id] ?? "" },
                    set: { settingsManager.setTargetOverride(source: layout.id, target: $0.isEmpty ? nil : $0) }
                )
            ) {
                Text(l10n.localized("layouts.target.auto")).tag("")
                Divider()
                ForEach(settingsManager.enabledLayouts.filter { $0.id != layout.id }) { other in
                    Text(other.localizedName).tag(other.id)
                }
            }
            .labelsHidden()
            .accessibilityLabel("\(l10n.localized("layouts.convertTo")), \(layout.localizedName)")
            .frame(width: Self.targetPickerWidth, alignment: .leading)
            .disabled(!enabled)
            .help(l10n.localized("layouts.target.help"))
        }
        .padding(.vertical, 2)
    }
}
