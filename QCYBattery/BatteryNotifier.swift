import Foundation
import UserNotifications

/// Entrega notificações de bateria baixa por lado, atrás de protocolo para os testes e previews usarem fake sem
/// tocar no `UNUserNotificationCenter`.
@MainActor
protocol BatteryNotifying: AnyObject {
    func requestAuthorization()
    func notify(_ alert: BatteryAlert)
}

/// Implementação nula usada como padrão em testes e previews.
@MainActor
final class NoOpBatteryNotifier: BatteryNotifying {
    func requestAuthorization() {}
    func notify(_ alert: BatteryAlert) {}
}

/// Implementação real via `UNUserNotificationCenter`. Só pede permissão sob demanda (nunca no lançamento) e envia
/// apenas o lado e a porcentagem, sem MAC ou nome do usuário.
@MainActor
final class UNBatteryNotifier: BatteryNotifying {
    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
    }

    func requestAuthorization() {
        Task { @MainActor in
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }

    func notify(_ alert: BatteryAlert) {
        let content = Self.content(for: alert)
        let identifier = "battery.\(alert.side.rawValue).\(alert.severity.rawValue)"
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: nil)
        Task { @MainActor in
            let settings = await center.notificationSettings()
            if settings.authorizationStatus == .notDetermined {
                guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
            }
            try? await center.add(request)
        }
    }

    static func content(for alert: BatteryAlert) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = localizedTitle(for: alert.severity)
        content.body = localizedBody(for: alert)
        content.sound = .default
        return content
    }

    static func localizedTitle(for severity: BatteryAlertSeverity) -> String {
        switch severity {
        case .low: String(localized: "qcy.alert.battery.low.title")
        case .critical: String(localized: "qcy.alert.battery.critical.title")
        }
    }

    static func localizedBody(for alert: BatteryAlert) -> String {
        let format: String = switch alert.side {
        case .left: String(localized: "qcy.alert.battery.left.body")
        case .right: String(localized: "qcy.alert.battery.right.body")
        }
        return String(format: format, locale: .current, Int64(alert.percent))
    }
}
