import Foundation
import Observation

/// Coordena o atalho global de ANC e as regras de ANC por contexto (chamada em andamento e Foco).
/// Permanece inerte quando não configurado: não registra atalho se `globalANCHotKey == nil` e não inicia o monitor
/// de áudio enquanto a regra de chamada estiver desligada.
@MainActor
@Observable
final class ContextRuleCoordinator {
    private(set) var activeFocusScene: QCYANCChoice?
    private(set) var isCallActive = false
    private(set) var hotKeyError: GlobalHotKeyError?
    var isRecordingHotKey = false

    @ObservationIgnored private let model: QCYViewModel
    @ObservationIgnored private let preferences: PreferencesModel
    @ObservationIgnored private let hotKeyRegistrar: any GlobalHotKeyRegistering
    @ObservationIgnored private let callMonitor: any CallActivityMonitoring
    @ObservationIgnored private let runnerFactory: @MainActor (QCYViewModel) -> QCYIntentRunner
    @ObservationIgnored private var policy = ContextRulePolicy()
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var callApplyTask: Task<Void, Never>?

    init(
        model: QCYViewModel,
        preferences: PreferencesModel,
        hotKeyRegistrar: any GlobalHotKeyRegistering = CarbonGlobalHotKeyRegistrar(),
        callMonitor: any CallActivityMonitoring = CoreAudioCallActivityMonitor(),
        runnerFactory: @escaping @MainActor (QCYViewModel) -> QCYIntentRunner = { QCYIntentRunner(model: $0) }
    ) {
        self.model = model
        self.preferences = preferences
        self.hotKeyRegistrar = hotKeyRegistrar
        self.callMonitor = callMonitor
        self.runnerFactory = runnerFactory
    }

    static func inert(model: QCYViewModel, preferences: PreferencesModel) -> ContextRuleCoordinator {
        ContextRuleCoordinator(
            model: model,
            preferences: preferences,
            hotKeyRegistrar: NoOpGlobalHotKeyRegistrar(),
            callMonitor: NoOpCallActivityMonitor()
        )
    }

    // MARK: - Ciclo de vida

    func start() {
        guard !isStarted else { return }
        isStarted = true

        hotKeyRegistrar.onTrigger = { [weak self] in
            self?.handleHotKeyTriggered()
        }
        callMonitor.onChange = { [weak self] active in
            self?.handleCallActivityChanged(active)
        }

        if let shortcut = preferences.globalANCHotKey {
            registerStoredHotKey(shortcut)
        }

        if preferences.callRuleEnabled {
            callMonitor.start()
            if callMonitor.isActive {
                handleCallActivityChanged(true)
            }
        }
    }

    func stop() {
        isStarted = false
        callApplyTask?.cancel()
        callApplyTask = nil
        hotKeyRegistrar.onTrigger = nil
        hotKeyRegistrar.unregister()
        callMonitor.onChange = nil
        callMonitor.stop()
        isCallActive = false
    }

    // MARK: - Atalho global

    @discardableResult
    func updateGlobalHotKey(_ shortcut: MacroKeyShortcut?) -> Bool {
        hotKeyError = nil
        guard let shortcut else {
            hotKeyRegistrar.unregister()
            preferences.setGlobalANCHotKey(nil)
            return true
        }
        guard !shortcut.modifiers.isEmpty else {
            hotKeyError = .missingModifiers
            return false
        }

        do {
            try hotKeyRegistrar.register(shortcut)
            preferences.setGlobalANCHotKey(shortcut)
            return true
        } catch let error as GlobalHotKeyError {
            hotKeyError = error
            return false
        } catch {
            hotKeyError = .registrationFailed(-1)
            return false
        }
    }

    func clearHotKeyError() {
        hotKeyError = nil
    }

    func reportMissingModifiers() {
        hotKeyError = .missingModifiers
    }

    func handleHotKeyTriggered() {
        guard !isRecordingHotKey else { return }
        model.cycleANC()
    }

    // MARK: - Regras de contexto

    func setCallRuleEnabled(_ enabled: Bool) {
        preferences.setCallRuleEnabled(enabled)
        guard isStarted else { return }

        if enabled {
            callMonitor.start()
            if callMonitor.isActive {
                handleCallActivityChanged(true)
            }
        } else {
            callMonitor.stop()
            let wasActive = isCallActive || policy.isActive(.call)
            isCallActive = false
            if wasActive {
                scheduleCallTransition(active: false)
            }
        }
    }

    func setCallRuleScene(_ scene: QCYANCChoice) {
        preferences.setCallRuleScene(scene)
        guard isStarted, preferences.callRuleEnabled, policy.isActive(.call) else { return }
        scheduleCallTransition(active: true)
    }

    func handleCallActivityChanged(_ active: Bool) {
        isCallActive = active
        if active && !preferences.callRuleEnabled {
            return
        }
        scheduleCallTransition(active: active)
    }

    /// Aplicado pelo `QCYFocusFilterIntent` quando um Foco com filtro do QCYBattery liga (`scene != nil`)
    /// ou desliga (`scene == nil`).
    func handleFocusFilter(_ scene: QCYANCChoice?) async {
        activeFocusScene = scene
        let runner = runnerFactory(model)
        if model.phase == .loading {
            try? await runner.waitForConnection()
        }

        let currentScene = model.ancSelection
        let target: QCYANCChoice?
        if let scene {
            target = policy.enterFocus(target: scene, currentScene: currentScene)
        } else {
            target = policy.exitFocus(currentScene: currentScene)
        }

        guard let target else { return }
        try? await runner.setNoiseMode(target)
    }

    // MARK: - Privado

    private func registerStoredHotKey(_ shortcut: MacroKeyShortcut) {
        do {
            try hotKeyRegistrar.register(shortcut)
            hotKeyError = nil
        } catch let error as GlobalHotKeyError {
            hotKeyError = error
        } catch {
            hotKeyError = .registrationFailed(-1)
        }
    }

    private func scheduleCallTransition(active: Bool) {
        callApplyTask?.cancel()
        callApplyTask = Task { @MainActor [weak self] in
            guard let self else { return }
            await self.applyCallTransition(active: active)
        }
    }

    private func applyCallTransition(active: Bool) async {
        let runner = runnerFactory(model)
        if model.phase == .loading {
            try? await runner.waitForConnection()
        }
        guard !Task.isCancelled else { return }

        let currentScene = model.ancSelection
        let target: QCYANCChoice?
        if active {
            target = policy.enterCall(
                settings: preferences.contextRuleSettings,
                currentScene: currentScene
            )
        } else {
            target = policy.exitCall(currentScene: currentScene)
        }

        guard let target, model.phase == .connected else { return }
        try? await runner.setNoiseMode(target)
    }
}
