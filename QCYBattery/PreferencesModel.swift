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

/// Preferências de presença (barra de menu e Dock) e abertura no login (US-06).
/// Pelo menos uma das visibilidades (barra de menu ou Dock) permanece sempre ativa.
@MainActor
@Observable
final class PreferencesModel {
    private enum Key {
        static let showInMenuBar = "preferences.showInMenuBar"
        static let showInDock = "preferences.showInDock"
    }

    private(set) var showInMenuBar: Bool
    private(set) var showInDock: Bool
    private(set) var launchAtLogin: Bool

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let policyApplier: any ActivationPolicyApplying
    @ObservationIgnored private let loginController: any LaunchAtLoginControlling

    init(
        defaults: UserDefaults = .standard,
        policyApplier: any ActivationPolicyApplying = AppActivationPolicyApplier(),
        loginController: any LaunchAtLoginControlling = SMAppServiceLaunchAtLogin()
    ) {
        self.defaults = defaults
        self.policyApplier = policyApplier
        self.loginController = loginController

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
}
