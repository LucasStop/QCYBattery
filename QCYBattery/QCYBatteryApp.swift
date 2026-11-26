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
        let contextCoordinator = sharedContextCoordinator
        AppDependencyManager.shared.add(dependency: model)
        AppDependencyManager.shared.add(dependency: contextCoordinator)
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
                macroStore: sharedMacroStore,
                contextCoordinator: sharedContextCoordinator
            )
        }
        .windowResizability(.contentSize)
        .commands {
            // Cmd+Q com a barra de menu ligada só fecha as janelas; "Encerrar" do popover e o Dock encerram de verdade.
            CommandGroup(replacing: .appTermination) {
                Button("qcy.menu.quitApp") {
                    if sharedPreferences.keepsRunningOnQuitShortcut {
                        NSApplication.shared.windows.forEach { $0.close() }
                    } else {
                        NSApplication.shared.terminate(nil)
                    }
                }
                .keyboardShortcut("q")
            }
        }

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
            // Largura fixa por quantidade de lados: se o item muda de tamanho ao aparecer a porcentagem, o macOS ancora
            // o popover na posição antiga e ele abre deslocado. O MenuBarExtra descarta símbolo embutido em Text e
            // descarta o símbolo `lb.*`: NSImage template ao lado do texto, na mesma linha de base.
            let label = sharedModel.menuBarLabel
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                MenuBarHeadphonesIcon(isConnected: sharedModel.phase == .connected)
                if sharedModel.isCharging {
                    Image(systemName: "bolt.fill")
                }
                if !label.isEmpty {
                    Text(label)
                        .monospacedDigit()
                }
            }
            .frame(width: label.isEmpty ? nil : (label.contains("·") ? 132 : 80), alignment: .leading)
        }
        .menuBarExtraStyle(.window)

        Settings {
            QCYSettingsView(preferences: sharedPreferences)
        }
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // O host dos testes é o app: sem isso ele escaneia Bluetooth e muda a política durante `xcodebuild test`.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        sharedPreferences.applyActivationPolicy()
        sharedModel.start()
        sharedMacroCoordinator.start()
        sharedContextCoordinator.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        sharedContextCoordinator.stop()
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
@MainActor private let sharedContextCoordinator = ContextRuleCoordinator(
    model: sharedModel,
    preferences: sharedPreferences
)
