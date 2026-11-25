import SwiftUI

/// Ajustes mínimos (Cmd+,) até a aba T16 chegar: presença na barra de menu/Dock e abrir no login.
struct QCYSettingsView: View {
    @Bindable var preferences: PreferencesModel

    var body: some View {
        Form {
            Section {
                Toggle("settings.showInMenuBar", isOn: Binding(
                    get: { preferences.showInMenuBar },
                    set: { preferences.setShowInMenuBar($0) }
                ))
                .disabled(!preferences.canTurnOffMenuBar)

                Toggle("settings.showInDock", isOn: Binding(
                    get: { preferences.showInDock },
                    set: { preferences.setShowInDock($0) }
                ))
                .disabled(!preferences.canTurnOffDock)
            } header: {
                Text("settings.section.presence")
            } footer: {
                Text("settings.visibility.hint")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("settings.section.startup") {
                Toggle("settings.launchAtLogin", isOn: Binding(
                    get: { preferences.launchAtLogin },
                    set: { preferences.setLaunchAtLogin($0) }
                ))
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { preferences.refreshLaunchAtLogin() }
    }
}

#if DEBUG
#Preview("Ajustes") {
    QCYSettingsView(preferences: PreferencesModel())
}
#endif
