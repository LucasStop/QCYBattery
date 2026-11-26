import SwiftUI

/// Linha "Atalho global do ANC" dentro do grupo "App e atalho" da aba Ajustes (T16, US-10).
struct QCYGlobalHotKeyRow: View {
    @Bindable var preferences: PreferencesModel
    @Bindable var contextCoordinator: ContextRuleCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                QCYLabel(title: "qcy.adjustments.hotkey.title", hint: "qcy.adjustments.hotkey.hint")
                Spacer(minLength: 8)
                QCYGlobalHotKeyRecorder(
                    shortcut: preferences.globalANCHotKey,
                    isRecording: Binding(
                        get: { contextCoordinator.isRecordingHotKey },
                        set: { recording in
                            if recording { contextCoordinator.clearHotKeyError() }
                            contextCoordinator.isRecordingHotKey = recording
                        }
                    ),
                    onRecord: { contextCoordinator.updateGlobalHotKey($0) },
                    onClear: { contextCoordinator.updateGlobalHotKey(nil) },
                    onMissingModifiers: { contextCoordinator.reportMissingModifiers() }
                )
            }
            if let error = contextCoordinator.hotKeyError, let message = error.errorDescription {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(BatteryLevel.critical.color)
            }
        }
        .padding(12)
    }
}

/// Seção "Regras de ANC por contexto" da aba Ajustes (T16, US-10): chamada em andamento e filtro de Foco do macOS.
struct QCYContextRulesGroup: View {
    @Bindable var preferences: PreferencesModel
    @Bindable var contextCoordinator: ContextRuleCoordinator

    var body: some View {
        QCYGroup {
            VStack(spacing: 0) {
                callRuleRow
                Divider()
                focusRuleRow
            }
        }
    }

    private var callRuleRow: some View {
        HStack(spacing: 12) {
            QCYLabel(title: "qcy.adjustments.rules.call.title", hint: "qcy.adjustments.rules.call.hint")
            Spacer(minLength: 8)
            HStack(spacing: 8) {
                Text("→")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Picker(selection: Binding(
                    get: { preferences.callRuleScene },
                    set: { contextCoordinator.setCallRuleScene($0) }
                )) {
                    ForEach(QCYANCChoice.allCases, id: \.self) { choice in
                        Text(choice.localizedTitle).tag(choice)
                    }
                } label: {
                    Text("qcy.adjustments.rules.call.scene")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("qcy.adjustments.rules.call.scene")

                Toggle(
                    "qcy.adjustments.rules.call.title",
                    isOn: Binding(
                        get: { preferences.callRuleEnabled },
                        set: { contextCoordinator.setCallRuleEnabled($0) }
                    )
                )
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
        .padding(12)
    }

    private var focusRuleRow: some View {
        HStack(spacing: 12) {
            QCYLabel(title: "qcy.adjustments.rules.focus.title", hint: "qcy.adjustments.rules.focus.hint")
            Spacer(minLength: 8)
            focusStatusBadge
        }
        .padding(12)
    }

    @ViewBuilder
    private var focusStatusBadge: some View {
        if let activeScene = contextCoordinator.activeFocusScene {
            HStack(spacing: 5) {
                Circle()
                    .fill(BatteryLevel.normal.color)
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(focusActiveLabel(for: activeScene))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .fixedSize()
        } else {
            Text("qcy.adjustments.rules.focus.inactive")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
        }
    }

    private func focusActiveLabel(for scene: QCYANCChoice) -> String {
        let sceneName = String(localized: scene.localizedResource)
        return String(
            format: String(localized: "qcy.adjustments.rules.focus.active"),
            locale: .current,
            sceneName
        )
    }
}

extension QCYANCChoice {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .anc: "qcy.anc.anc"
        case .normal: "qcy.anc.normal"
        case .transparency: "qcy.anc.transparency"
        }
    }

    var localizedResource: LocalizedStringResource {
        switch self {
        case .anc: "qcy.anc.anc"
        case .normal: "qcy.anc.normal"
        case .transparency: "qcy.anc.transparency"
        }
    }
}
