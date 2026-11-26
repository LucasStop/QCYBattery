#if DEBUG
import AppKit
import Foundation
import QCYKit

/// Link de mentira só para o canvas do Xcode: não fala com o fone, devolve o estado que o preview injeta.
final class PreviewQCYLink: QCYLink, @unchecked Sendable {
    var onState: (@Sendable (QCYState) -> Void)?
    var onAdvertisement: (@Sendable (QCYAdvertisement) -> Void)?
    var onReady: (@Sendable () -> Void)?
    var onDisconnect: (@Sendable () -> Void)?
    func start() {}
    func stop() {}
    func refresh() {}
    func refreshKeyMap() {}
    func send(_ packet: QCYPacket) {}
    func setKeyFunction(_ function: QCYKeyFunction, for gesture: QCYGesture) {}
}

@MainActor
private final class PreviewActivationPolicyApplier: ActivationPolicyApplying {
    func apply(_ policy: NSApplication.ActivationPolicy) {}
}

@MainActor
private final class PreviewLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool
    init(isEnabled: Bool) { self.isEnabled = isEnabled }
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}

private struct PreviewMacroEffects: MacroEffects, Sendable {
    func postKey(_ shortcut: MacroKeyShortcut) async throws {}
    func open(_ target: MacroOpenTarget) async throws {}
    func runProcess(
        executableURL: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> MacroProcessOutput {
        MacroProcessOutput(exitCode: 0, wasTruncated: false)
    }
}

@MainActor
func previewMacroStore(macros: [Macro] = []) -> MacroStore {
    MacroStore.inMemory(macros: macros)
}

func previewMacroRunner() -> MacroRunner {
    MacroRunner(effects: PreviewMacroEffects())
}

enum PreviewScenario { case connected, charging, loading, disconnected }

@MainActor
func previewModel(
    _ scenario: PreviewScenario,
    readOnly: Bool = false,
    macroStore: MacroStore = .inMemory()
) -> QCYViewModel {
    let link = PreviewQCYLink()
    let model = QCYViewModel(link: link, isReadOnly: readOnly, macroStore: macroStore)
    switch scenario {
    case .connected:
        var state = QCYState()
        state.left = QCYBatteryLevel(raw: 90)
        state.right = QCYBatteryLevel(raw: 91)
        state.ancScene = QCYANScene(mode: 0x03, subScene: 0x02, noiseValue: 0x00)
        state.isLDACEnabled = true
        state.isLowLatencyEnabled = false
        state.soundEffect = .spatial
        state.balance = 42
        state.powerOff = .fifteenMinutes
        state.toneVolume = .medium
        state.wearDetection = QCYWearDetection(
            isEnabled: true,
            musicControl: .pauseAndResume,
            isANCSwitchEnabled: false
        )
        state.keyMap = [
            .leftSingleTap: .unassigned,
            .rightSingleTap: .playPause,
            .leftDoubleTap: .previousTrack,
            .rightDoubleTap: .nextTrack,
            .leftTripleTap: .ancMode,
            .rightTripleTap: .voiceAssistant
        ]
        link.onState?(state)
    case .charging:
        var state = QCYState()
        state.left = QCYBatteryLevel(raw: 0x80 | 84)
        state.right = QCYBatteryLevel(raw: 0x80 | 86)
        state.ancScene = QCYANScene(mode: 0x02, subScene: 0x00, noiseValue: 0x00)
        state.soundEffect = .default
        state.balance = 50
        state.powerOff = .disabled
        state.toneVolume = .lower
        link.onState?(state)
    case .loading:
        break
    case .disconnected:
        link.onDisconnect?()
    }
    return model
}

@MainActor
func previewPreferences(
    showInMenuBar: Bool = true,
    showInDock: Bool = true,
    launchAtLogin: Bool = true,
    lowBatteryAlertEnabled: Bool = true,
    criticalBatteryAlertEnabled: Bool = true,
    globalANCHotKey: MacroKeyShortcut? = nil,
    callRuleEnabled: Bool = true,
    callRuleScene: QCYANCChoice = .transparency
) -> PreferencesModel {
    let suiteName = "com.lucasstop.QCYBattery.preview.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName) ?? .standard
    defaults.set(showInMenuBar, forKey: "preferences.showInMenuBar")
    defaults.set(showInDock, forKey: "preferences.showInDock")
    defaults.set(lowBatteryAlertEnabled, forKey: "preferences.lowBatteryAlert")
    defaults.set(criticalBatteryAlertEnabled, forKey: "preferences.criticalBatteryAlert")
    defaults.set(callRuleEnabled, forKey: "preferences.contextRule.call.enabled")
    defaults.set(callRuleScene.rawValue, forKey: "preferences.contextRule.call.scene")
    if let globalANCHotKey, let data = try? JSONEncoder().encode(globalANCHotKey) {
        defaults.set(data, forKey: "preferences.globalANCHotKey")
    }
    return PreferencesModel(
        defaults: defaults,
        policyApplier: PreviewActivationPolicyApplier(),
        loginController: PreviewLaunchAtLoginController(isEnabled: launchAtLogin),
        notifier: NoOpBatteryNotifier()
    )
}

@MainActor
func previewContextCoordinator(
    model: QCYViewModel,
    preferences: PreferencesModel,
    isRecordingHotKey: Bool = false
) -> ContextRuleCoordinator {
    let coordinator = ContextRuleCoordinator(
        model: model,
        preferences: preferences,
        hotKeyRegistrar: NoOpGlobalHotKeyRegistrar(),
        callMonitor: NoOpCallActivityMonitor()
    )
    coordinator.isRecordingHotKey = isRecordingHotKey
    return coordinator
}

@MainActor
func previewWindow(
    _ scenario: PreviewScenario = .connected,
    readOnly: Bool = false,
    tab: QCYTab = .status
) -> QCYView {
    let model = previewModel(scenario, readOnly: readOnly)
    let preferences = previewPreferences()
    return QCYView(
        model: model,
        preferences: preferences,
        contextCoordinator: previewContextCoordinator(model: model, preferences: preferences),
        selectedTab: tab
    )
}
#endif
