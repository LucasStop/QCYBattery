import QCYKit
import SwiftUI

/// Aba Ajustes da janela principal (T16): ajustes do fone (desligamento automático, volume dos avisos e detecção de
/// uso), preferências do app (barra de menu, Dock e abrir ao iniciar sessão) e alertas de bateria baixa por lado.
struct QCYAdjustmentsView: View {
    @Bindable var model: QCYViewModel
    @Bindable var preferences: PreferencesModel

    private static let powerOffPresets: [QCYPowerOff] = [
        .disabled, .fifteenMinutes, .thirtyMinutes, .sixtyMinutes, .ninetyMinutes
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QCYStatusBanner(model: model)
            sectionHeader("qcy.adjustments.section.earbuds")
            earbudsGroup
            sectionHeader("qcy.adjustments.section.app")
            QCYAppPreferencesGroup(preferences: preferences)
            sectionHeader("qcy.adjustments.section.batteryAlerts")
            batteryAlertsGroup
        }
    }

    private func sectionHeader(_ title: LocalizedStringKey) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.4)
            .padding(.horizontal, 4)
            .padding(.bottom, -6)
    }

    // MARK: - Fone

    private var earbudsGroup: some View {
        QCYGroup {
            VStack(spacing: 0) {
                powerOffRow
                    .disabled(model.areControlsDisabled)
                    .opacity(model.areControlsDisabled && model.pending == nil ? 0.55 : 1)
                Divider()
                QCYToneVolumeSlider(volume: model.toneVolume) { volume in
                    model.choose(toneVolume: volume)
                }
                .padding(12)
                .disabled(model.areControlsDisabled)
                .opacity(model.areControlsDisabled && model.pending == nil ? 0.55 : 1)
                Divider()
                wearDetectionRow
            }
        }
    }

    private var powerOffRow: some View {
        HStack(spacing: 12) {
            QCYLabel(title: "qcy.adjustments.powerOff.title", hint: "qcy.adjustments.powerOff.hint")
            Spacer(minLength: 8)
            Picker(selection: powerOffBinding) {
                if model.powerOff == nil {
                    Text("—").tag(Optional<QCYPowerOff>.none)
                } else if let current = model.powerOff, !Self.powerOffPresets.contains(current) {
                    Text(current.localizedTitle).tag(Optional(current))
                }
                ForEach(Self.powerOffPresets, id: \.self) { option in
                    Text(option.localizedTitle).tag(Optional(option))
                }
            } label: {
                Text("qcy.adjustments.powerOff.title")
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .fixedSize()
            .accessibilityLabel("qcy.adjustments.powerOff.title")
        }
        .padding(12)
    }

    private var powerOffBinding: Binding<QCYPowerOff?> {
        Binding(
            get: { model.powerOff },
            set: { newValue in
                if let newValue {
                    model.choose(powerOff: newValue)
                }
            }
        )
    }

    private var wearDetectionRow: some View {
        let isRowDisabled = model.areControlsDisabled || !model.isWearDetectionAvailable
        let isDimmed = (model.areControlsDisabled && model.pending == nil) || !model.isWearDetectionAvailable

        return HStack(spacing: 12) {
            QCYLabel(title: "qcy.adjustments.wearDetection.title", hint: "qcy.adjustments.wearDetection.hint")
            Spacer(minLength: 8)
            Toggle(
                "qcy.adjustments.wearDetection.title",
                isOn: Binding(get: { model.isWearDetectionOn }, set: { model.setWearDetection($0) })
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(12)
        .disabled(isRowDisabled)
        .opacity(isDimmed ? 0.55 : 1)
    }

    // MARK: - Alertas de bateria baixa

    private var batteryAlertsGroup: some View {
        QCYGroup {
            VStack(spacing: 0) {
                batteryAlertRow(
                    dotColor: BatteryLevel.low.color,
                    title: "qcy.adjustments.batteryAlerts.low.title",
                    hint: "qcy.adjustments.batteryAlerts.low.hint",
                    isOn: Binding(
                        get: { preferences.lowBatteryAlertEnabled },
                        set: { preferences.setLowBatteryAlert($0) }
                    )
                )
                Divider()
                batteryAlertRow(
                    dotColor: BatteryLevel.critical.color,
                    title: "qcy.adjustments.batteryAlerts.critical.title",
                    hint: "qcy.adjustments.batteryAlerts.critical.hint",
                    isOn: Binding(
                        get: { preferences.criticalBatteryAlertEnabled },
                        set: { preferences.setCriticalBatteryAlert($0) }
                    )
                )
            }
        }
    }

    private func batteryAlertRow(
        dotColor: Color,
        title: LocalizedStringKey,
        hint: LocalizedStringKey,
        isOn: Binding<Bool>
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(dotColor)
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    Text(title)
                }
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .padding(12)
    }
}

// MARK: - Slider de volume dos avisos

/// Slider em 4 passos discretos para `QCYToneVolume` que só envia ao fone ao soltar (DESIGN.md).
struct QCYToneVolumeSlider: View {
    let volume: QCYToneVolume?
    let onCommit: (QCYToneVolume) -> Void

    @State private var draft: Double
    @State private var isDragging = false

    init(volume: QCYToneVolume?, onCommit: @escaping (QCYToneVolume) -> Void) {
        self.volume = volume
        self.onCommit = onCommit
        _draft = State(initialValue: Double(Self.index(for: volume ?? .medium)))
    }

    private var displayedVolume: QCYToneVolume {
        Self.volume(for: Int(draft.rounded()))
    }

    var body: some View {
        HStack(spacing: 12) {
            QCYLabel(title: "qcy.adjustments.toneVolume.title", hint: "qcy.adjustments.toneVolume.hint")
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Slider(
                    value: $draft,
                    in: 0...Double(QCYToneVolume.allCases.count - 1),
                    step: 1
                ) {
                    Text("qcy.adjustments.toneVolume.title")
                } onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        onCommit(displayedVolume)
                    }
                }
                .labelsHidden()
                .frame(width: 108)

                Group {
                    if volume != nil || isDragging {
                        Text(displayedVolume.localizedTitle)
                    } else {
                        Text("—")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 68, alignment: .trailing)
            }
        }
        .onChange(of: volume) { _, newValue in
            if !isDragging, let newValue {
                draft = Double(Self.index(for: newValue))
            }
        }
    }

    static func index(for volume: QCYToneVolume) -> Int {
        QCYToneVolume.allCases.firstIndex(of: volume) ?? 0
    }

    static func volume(for index: Int) -> QCYToneVolume {
        let cases = QCYToneVolume.allCases
        let clamped = min(max(index, 0), cases.count - 1)
        return cases[clamped]
    }
}

// MARK: - Rótulos localizados

extension QCYPowerOff {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .disabled: "qcy.adjustments.powerOff.disabled"
        case .minutes(15): "qcy.adjustments.powerOff.15"
        case .minutes(30): "qcy.adjustments.powerOff.30"
        case .minutes(60): "qcy.adjustments.powerOff.60"
        case .minutes(90): "qcy.adjustments.powerOff.90"
        case .minutes(let minutes): LocalizedStringKey("\(minutes) min")
        }
    }
}

extension QCYToneVolume {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .lower: "qcy.adjustments.toneVolume.lower"
        case .medium: "qcy.adjustments.toneVolume.medium"
        case .higher: "qcy.adjustments.toneVolume.higher"
        case .maximum: "qcy.adjustments.toneVolume.maximum"
        }
    }
}

#if DEBUG
#Preview("Aba Ajustes — conectado") {
    QCYAdjustmentsView(model: previewModel(.connected), preferences: previewPreferences())
        .padding(16)
        .frame(width: 468)
}
#Preview("Aba Ajustes — só barra de menu") {
    QCYAdjustmentsView(
        model: previewModel(.connected),
        preferences: previewPreferences(showInMenuBar: true, showInDock: false)
    )
    .padding(16)
    .frame(width: 468)
}
#Preview("Aba Ajustes — somente leitura") {
    QCYAdjustmentsView(model: previewModel(.connected, readOnly: true), preferences: previewPreferences())
        .padding(16)
        .frame(width: 468)
}
#Preview("Aba Ajustes — sem conexão") {
    QCYAdjustmentsView(model: previewModel(.disconnected), preferences: previewPreferences())
        .padding(16)
        .frame(width: 468)
}
#endif
