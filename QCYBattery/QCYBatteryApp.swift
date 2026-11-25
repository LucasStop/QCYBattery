import AppIntents
import AppKit
import QCYKit
import SwiftUI

/// App do fone QCY: janela principal (T12), item na barra de menu com popover (T13) e ajustes mínimos (Cmd+,).
@main
struct QCYBatteryApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @Environment(\.openWindow) private var openWindow

    init() {
        let model = sharedModel
        AppDependencyManager.shared.add(dependency: model)
    }

    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { sharedPreferences.showInMenuBar },
            set: { sharedPreferences.setShowInMenuBar($0) }
        )
    }

    var body: some Scene {
        Window("qcy.window", id: "main") {
            QCYView(
                model: sharedModel,
                preferences: sharedPreferences,
                macroStore: sharedMacroStore
            )
        }
        .windowResizability(.contentSize)

        MenuBarExtra(isInserted: menuBarInserted) {
            QCYMenuBarPopover(
                model: sharedModel,
                openMainWindow: {
                    openWindow(id: "main")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                },
                quitApp: { NSApplication.shared.terminate(nil) }
            )
        } label: {
            // Largura fixa: se o item muda de tamanho ao aparecer a porcentagem, o macOS ancora o popover
            // na posição antiga e ele abre deslocado para a direita.
            HStack(spacing: 4) {
                if sharedModel.phase == .connected {
                    Image("lb.headphones.bluetooth")
                } else {
                    Image(systemName: "headphones")
                }
                if sharedModel.isCharging {
                    Image(systemName: "bolt.fill")
                }
                Text(sharedModel.menuBarText)
                    .monospacedDigit()
            }
            .frame(width: 132, alignment: .leading)
        }
        .menuBarExtraStyle(.window)

        Settings {
            QCYSettingsView(preferences: sharedPreferences)
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // O host dos testes é o app: sem isso ele escaneia Bluetooth e muda a política durante `xcodebuild test`.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        sharedPreferences.applyActivationPolicy()
        sharedModel.start()
        sharedMacroCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        sharedMacroCoordinator.stop()
    }
}

/// Instâncias únicas: o ciclo de vida no `AppDelegate`, a janela e o item da barra de menu enxergam o mesmo estado.
@MainActor private let sharedNotifier = UNBatteryNotifier()
@MainActor private let sharedPreferences = PreferencesModel(notifier: sharedNotifier)
@MainActor private let sharedMacroStore = MacroStore()
@MainActor private let sharedMacroCoordinator = MacroCoordinator(store: sharedMacroStore)
@MainActor private let sharedModel = QCYViewModel(
    link: QCYClient(),
    isReadOnly: CommandLine.arguments.contains("--read-only"),
    notifier: sharedNotifier,
    alertSettings: { sharedPreferences.batteryAlertSettings },
    macroStore: sharedMacroStore
)
