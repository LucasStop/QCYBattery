import AppKit
import Foundation
import Observation
import ServiceManagement

/// Abstração da política de ativação do app no macOS para os testes validarem sem tocar no `NSApp`.
@MainActor
protocol ActivationPolicyApplying: AnyObject {
    func apply(_ policy: NSApplication.ActivationPolicy)
}

@MainActor
final class AppActivationPolicyApplier: ActivationPolicyApplying {
    func apply(_ policy: NSApplication.ActivationPolicy) {
        NSApplication.shared.setActivationPolicy(policy)
    }
}

/// Abstração de `SMAppService.mainApp` para os testes não mexerem nos itens de login reais.
@MainActor
protocol LaunchAtLoginControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
final class SMAppServiceLaunchAtLogin: LaunchAtLoginControlling {
    var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

/// Preferências de presença (barra de menu e Dock), abertura no login (US-06), atalho global e regras de ANC por
/// contexto (US-10) e alertas de bateria baixa (US-11).
/// Pelo menos uma das visibilidades (barra de menu ou Dock) permanece sempre ativa.
@MainActor
@Observable
final class PreferencesModel {
    private enum Key {
        static let showInMenuBar = "preferences.showInMenuBar"
        static let showInDock = "preferences.showInDock"
        static let lowBatteryAlert = "preferences.lowBatteryAlert"
        static let criticalBatteryAlert = "preferences.criticalBatteryAlert"
        static let globalANCHotKey = "preferences.globalANCHotKey"
        static let callRuleEnabled = "preferences.contextRule.call.enabled"
        static let callRuleScene = "preferences.contextRule.call.scene"
    }

    private(set) var showInMenuBar: Bool
    private(set) var showInDock: Bool
    private(set) var launchAtLogin: Bool
    private(set) var lowBatteryAlertEnabled: Bool
    private(set) var criticalBatteryAlertEnabled: Bool
    private(set) var globalANCHotKey: MacroKeyShortcut?
    private(set) var callRuleEnabled: Bool
    private(set) var callRuleScene: QCYANCChoice

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let policyApplier: any ActivationPolicyApplying
    @ObservationIgnored private let loginController: any LaunchAtLoginControlling
    @ObservationIgnored private let notifier: any BatteryNotifying
    @ObservationIgnored private var hasRequestedNotificationAuthorization = false

    init(
        defaults: UserDefaults = .standard,
        policyApplier: any ActivationPolicyApplying = AppActivationPolicyApplier(),
        loginController: any LaunchAtLoginControlling = SMAppServiceLaunchAtLogin(),
        notifier: any BatteryNotifying = NoOpBatteryNotifier()
    ) {
        self.defaults = defaults
        self.policyApplier = policyApplier
        self.loginController = loginController
        self.notifier = notifier

        let storedMenuBar = defaults.object(forKey: Key.showInMenuBar) as? Bool ?? true
        let storedDock = defaults.object(forKey: Key.showInDock) as? Bool ?? true
        if !storedMenuBar && !storedDock {
            self.showInMenuBar = true
            self.showInDock = false
        } else {
            self.showInMenuBar = storedMenuBar
            self.showInDock = storedDock
        }
        self.launchAtLogin = loginController.isEnabled
        self.lowBatteryAlertEnabled = defaults.object(forKey: Key.lowBatteryAlert) as? Bool ?? true
        self.criticalBatteryAlertEnabled = defaults.object(forKey: Key.criticalBatteryAlert) as? Bool ?? true
        self.globalANCHotKey = Self.decodeHotKey(from: defaults.data(forKey: Key.globalANCHotKey))
        self.callRuleEnabled = defaults.object(forKey: Key.callRuleEnabled) as? Bool
            ?? ContextRuleSettings.default.callEnabled
        let rawCallScene = defaults.string(forKey: Key.callRuleScene)
        self.callRuleScene = rawCallScene.flatMap(QCYANCChoice.init(rawValue:))
            ?? ContextRuleSettings.default.callScene
    }

    var batteryAlertSettings: BatteryAlertSettings {
        BatteryAlertSettings(
            lowEnabled: lowBatteryAlertEnabled,
            criticalEnabled: criticalBatteryAlertEnabled
        )
    }

    var contextRuleSettings: ContextRuleSettings {
        ContextRuleSettings(
            callEnabled: callRuleEnabled,
            callScene: callRuleScene
        )
    }

    var activationPolicy: NSApplication.ActivationPolicy {
        showInDock ? .regular : .accessory
    }

    var canTurnOffMenuBar: Bool { showInDock }
    var canTurnOffDock: Bool { showInMenuBar }

    @discardableResult
    func setShowInMenuBar(_ value: Bool) -> Bool {
        guard value || showInDock else { return false }
        guard value != showInMenuBar else { return true }
        showInMenuBar = value
        defaults.set(value, forKey: Key.showInMenuBar)
        return true
    }

    @discardableResult
    func setShowInDock(_ value: Bool) -> Bool {
        guard value || showInMenuBar else { return false }
        guard value != showInDock else { return true }
        showInDock = value
        defaults.set(value, forKey: Key.showInDock)
        policyApplier.apply(activationPolicy)
        return true
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        try? loginController.setEnabled(enabled)
        launchAtLogin = loginController.isEnabled
    }

    func refreshLaunchAtLogin() {
        launchAtLogin = loginController.isEnabled
    }

    func applyActivationPolicy() {
        policyApplier.apply(activationPolicy)
    }

    func setLowBatteryAlert(_ enabled: Bool) {
        guard enabled != lowBatteryAlertEnabled else { return }
        lowBatteryAlertEnabled = enabled
        defaults.set(enabled, forKey: Key.lowBatteryAlert)
        if enabled {
            requestNotificationAuthorizationIfNeeded()
        }
    }

    func setCriticalBatteryAlert(_ enabled: Bool) {
        guard enabled != criticalBatteryAlertEnabled else { return }
        criticalBatteryAlertEnabled = enabled
        defaults.set(enabled, forKey: Key.criticalBatteryAlert)
        if enabled {
            requestNotificationAuthorizationIfNeeded()
        }
    }

    func setGlobalANCHotKey(_ shortcut: MacroKeyShortcut?) {
        guard shortcut != globalANCHotKey else { return }
        globalANCHotKey = shortcut
        if let shortcut, let data = try? JSONEncoder().encode(shortcut) {
            defaults.set(data, forKey: Key.globalANCHotKey)
        } else {
            defaults.removeObject(forKey: Key.globalANCHotKey)
        }
    }

    func setCallRuleEnabled(_ enabled: Bool) {
        guard enabled != callRuleEnabled else { return }
        callRuleEnabled = enabled
        defaults.set(enabled, forKey: Key.callRuleEnabled)
    }

    func setCallRuleScene(_ scene: QCYANCChoice) {
        guard scene != callRuleScene else { return }
        callRuleScene = scene
        defaults.set(scene.rawValue, forKey: Key.callRuleScene)
    }

    private func requestNotificationAuthorizationIfNeeded() {
        guard !hasRequestedNotificationAuthorization else { return }
        hasRequestedNotificationAuthorization = true
        notifier.requestAuthorization()
    }

    private static func decodeHotKey(from data: Data?) -> MacroKeyShortcut? {
        guard let data,
              let decoded = try? JSONDecoder().decode(MacroKeyShortcut.self, from: data),
              !decoded.modifiers.isEmpty else {
            return nil
        }
        return decoded
    }
}
