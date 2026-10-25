import SwiftUI

/// Settings tab of the conversion log: logging switches, the entries table, export.
struct ConversionLogView: View {
    @ObservedObject var logStore: ConversionLogStore
    @EnvironmentObject private var settingsManager: SettingsManager
    @EnvironmentObject private var l10n: LocalizationManager
    @State private var showClearConfirmation = false
    @State private var selection = Set<ConversionLog.ID>()
    @State private var sortOrder = [KeyPathComparator(\ConversionLog.timestamp, order: .reverse)]

    private static let maxEntriesRange = 1...100_000
    private static let maxEntriesStep = 50

    /// "Unlimited" is stored as logMaxEntries == 0.
    private var isUnlimited: Binding<Bool> {
        Binding(
            get: { settingsManager.logMaxEntries == 0 },
            set: { newValue in
                settingsManager.logMaxEntries = newValue ? 0 : SettingsManager.defaultLogMaxEntries
            }
        )
    }

    private var sortedLogs: [ConversionLog] {
        logStore.logs.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    Toggle(l10n.localized("general.loggingEnabled"), isOn: $settingsManager.loggingEnabled)
                    if settingsManager.loggingEnabled {
                        Toggle(l10n.localized("log.unlimited"), isOn: isUnlimited)
                        if !isUnlimited.wrappedValue {
                            Stepper(
                                value: $settingsManager.logMaxEntries, in: Self.maxEntriesRange,
                                step: Self.maxEntriesStep
                            ) {
                                LabeledContent(l10n.localized("log.keepEntries")) {
                                    Text(settingsManager.logMaxEntries, format: .number)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                } footer: {
                    Text(l10n.localized("general.loggingDisabledNote"))
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .fixedSize(horizontal: false, vertical: true)

            if !settingsManager.loggingEnabled {
                ContentUnavailableView(
                    l10n.localized("log.disabledTitle"),
                    systemImage: "eye.slash",
                    description: Text(l10n.localized("log.disabledHint"))
                )
                .frame(maxHeight: .infinity)
            } else if logStore.logs.isEmpty {
                ContentUnavailableView(
                    l10n.localized("log.emptyTitle"),
                    systemImage: "text.badge.checkmark",
                    description: Text(l10n.localized("log.emptyHint"))
                )
                .frame(maxHeight: .infinity)
            } else {
                logTable
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                HStack {
                    Text(l10n.localized("log.entries").replacingOccurrences(of: "%d", with: "\(logStore.logs.count)"))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(l10n.localized("log.exportJSON")) {
                        exportJSON()
                    }
                    Button(l10n.localized("log.clearAll"), role: .destructive) {
                        showClearConfirmation = true
                    }
                }
                .padding(12)
            }
        }
        .settingsTabFrame()
        .onAppear {
            if settingsManager.loggingEnabled {
                logStore.loadIfNeeded()
            }
        }
        .onChange(of: settingsManager.loggingEnabled) { _, enabled in
            logStore.setLoggingEnabled(enabled)
        }
        .confirmationDialog(l10n.localized("log.clearConfirmTitle"), isPresented: $showClearConfirmation) {
            Button(l10n.localized("log.clearAll"), role: .destructive) {
                logStore.clearAll()
            }
            Button(l10n.localized("log.cancel"), role: .cancel) {}
        } message: {
            Text(l10n.localized("log.clearConfirmMessage"))
        }
    }

    // MARK: - Table

    private var logTable: some View {
        Table(sortedLogs, selection: $selection, sortOrder: $sortOrder) {
            TableColumn(l10n.localized("log.column.rating"), value: \.ratingSortKey) { entry in
                Button {
                    logStore.updateRating(id: entry.id, isCorrect: entry.nextRating)
                } label: {
                    ratingIcon(entry.isCorrect)
                }
                .buttonStyle(.borderless)
                .help(ratingTooltip(entry.isCorrect))
                .accessibilityLabel(ratingTooltip(entry.isCorrect))
            }
            .width(min: 44, ideal: 52, max: 60)

            TableColumn(l10n.localized("log.column.time"), value: \.timestamp) { entry in
                Text(entry.timestamp, format: .dateTime.day().month().hour().minute().second())
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 130, max: 160)

            TableColumn(l10n.localized("log.column.input"), value: \.inputText) { entry in
                Text(entry.inputText).lineLimit(1).truncationMode(.tail).help(entry.inputText)
            }
            .width(min: 80, ideal: 110, max: 400)

            TableColumn(l10n.localized("log.column.output"), value: \.outputText) { entry in
                Text(entry.outputText).lineLimit(1).truncationMode(.tail).help(entry.outputText)
            }
            .width(min: 80, ideal: 110, max: 400)

            TableColumn(l10n.localized("log.column.layouts"), value: \.layoutsDescription) { entry in
                Text(entry.layoutsDescription)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(entry.conversionMode)
            }
            .width(min: 90, ideal: 120, max: 220)
        }
        .contextMenu(forSelectionType: ConversionLog.ID.self) { ids in
            Button(l10n.localized("log.markCorrect")) { rate(ids, true) }
            Button(l10n.localized("log.markIncorrect")) { rate(ids, false) }
            Button(l10n.localized("log.clearRating")) { rate(ids, nil) }
            Divider()
            Button(l10n.localized("log.delete"), role: .destructive) { delete(ids) }
        }
        .onDeleteCommand { delete(selection) }
        // Keyboard: Space cycles the rating of the selected entries
        .onKeyPress(.space) {
            guard !selection.isEmpty else { return .ignored }
            for entry in logStore.logs where selection.contains(entry.id) {
                logStore.updateRating(id: entry.id, isCorrect: entry.nextRating)
            }
            return .handled
        }
    }

    @ViewBuilder
    private func ratingIcon(_ isCorrect: Bool?) -> some View {
        switch isCorrect {
        case nil:
            Image(systemName: "circle")
                .foregroundStyle(.secondary)
        case true?:
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.multicolor)
        case false?:
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.multicolor)
        }
    }

    private func ratingTooltip(_ isCorrect: Bool?) -> String {
        switch isCorrect {
        case nil: return l10n.localized("log.ratingUnrated")
        case true?: return l10n.localized("log.ratingCorrect")
        case false?: return l10n.localized("log.ratingIncorrect")
        }
    }

    private func rate(_ ids: Set<ConversionLog.ID>, _ isCorrect: Bool?) {
        for id in ids {
            logStore.updateRating(id: id, isCorrect: isCorrect)
        }
    }

    private func delete(_ ids: Set<ConversionLog.ID>) {
        for id in ids {
            logStore.delete(id: id)
        }
        selection.subtract(ids)
    }

    // MARK: - Export

    private func exportJSON() {
        let json = logStore.exportJSON()

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "conversion_log.json"
        panel.title = l10n.localized("log.exportPanelTitle")

        if panel.runModal() == .OK, let url = panel.url {
            do {
                try json.write(to: url, atomically: true, encoding: .utf8)
                Log.logStore.info("Exported \(logStore.logs.count) log entries")
                Log.logStore.debug("Export path: \(url.path, privacy: .private)")
            } catch {
                Log.logStore.error("Export failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
