import SwiftUI

/// Linhas de presença (barra de menu / Dock) e abrir ao iniciar sessão, compartilhadas entre a aba Ajustes (T16)
/// e a janela de ajustes do app (`Cmd+,`).
struct QCYAppPreferencesGroup: View {
    @Bindable var preferences: PreferencesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            QCYGroup {
                VStack(spacing: 0) {
                    menuBarRow
                    Divider()
                    dockRow
                    Divider()
                    launchAtLoginRow
                }
            }
            Text("settings.visibility.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .onAppear { preferences.refreshLaunchAtLogin() }
    }

    private var menuBarRow: some View {
        let isLocked = !preferences.canTurnOffMenuBar
        return HStack(spacing: 12) {
            QCYLabel(
                title: "settings.showInMenuBar",
                hint: isLocked ? "settings.showInMenuBar.locked" : "settings.showInMenuBar.hint"
            )
            Spacer(minLength: 8)
            Toggle("settings.showInMenuBar", isOn: Binding(
                get: { preferences.showInMenuBar },
                set: { preferences.setShowInMenuBar($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(12)
        .disabled(isLocked)
        .opacity(isLocked ? 0.55 : 1)
    }

    private var dockRow: some View {
        let isLocked = !preferences.canTurnOffDock
        return HStack(spacing: 12) {
            QCYLabel(
                title: "settings.showInDock",
                hint: isLocked ? "settings.showInDock.locked" : "settings.showInDock.hint"
            )
            Spacer(minLength: 8)
            Toggle("settings.showInDock", isOn: Binding(
                get: { preferences.showInDock },
                set: { preferences.setShowInDock($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(12)
        .disabled(isLocked)
        .opacity(isLocked ? 0.55 : 1)
    }

    private var launchAtLoginRow: some View {
        HStack(spacing: 12) {
            QCYLabel(title: "settings.launchAtLogin", hint: "settings.launchAtLogin.hint")
            Spacer(minLength: 8)
            Toggle("settings.launchAtLogin", isOn: Binding(
                get: { preferences.launchAtLogin },
                set: { preferences.setLaunchAtLogin($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(12)
    }
}

/// Janela de ajustes do app (`Cmd+,`), reutilizando as mesmas linhas da seção App da aba Ajustes (T16).
struct QCYSettingsView: View {
    @Bindable var preferences: PreferencesModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            QCYAppPreferencesGroup(preferences: preferences)
        }
        .padding(16)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
#Preview("Ajustes") {
    QCYSettingsView(preferences: previewPreferences())
}
#endif
