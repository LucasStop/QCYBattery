import Foundation
import QCYKit

/// Lado do fone monitorado pelos alertas de bateria baixa (US-11).
enum BatteryAlertSide: String, CaseIterable, Hashable, Sendable {
    case left
    case right
}

/// Faixa de alerta de bateria baixa: aviso em 20% ou crítico em 10%.
enum BatteryAlertSeverity: Int, Hashable, Sendable {
    case low = 20
    case critical = 10

    /// Histerese acima do limite para rearmar o alerta sem oscilar em torno da borda.
    static let hysteresis = 5

    var threshold: Int { rawValue }
    var rearmThreshold: Int { threshold + Self.hysteresis }
}

/// Evento de notificação decidido pela política para um lado do fone.
struct BatteryAlert: Equatable, Sendable {
    let side: BatteryAlertSide
    let severity: BatteryAlertSeverity
    let percent: Int
}

/// Quais limites de alerta estão habilitados nas preferências do usuário.
struct BatteryAlertSettings: Equatable, Sendable {
    var lowEnabled: Bool
    var criticalEnabled: Bool

    static let allEnabled = BatteryAlertSettings(lowEnabled: true, criticalEnabled: true)
    static let allDisabled = BatteryAlertSettings(lowEnabled: false, criticalEnabled: false)
}

/// Política pura de disparo e rearme de alertas de bateria baixa por lado (US-11).
///
/// Para cada lado (`L` e `R`) e cada limite (20% e 10%), dispara no máximo uma vez quando o nível cai para
/// `<= limite` sem estar carregando. Rearma quando o lado começa a carregar ou sobe acima de `limite + 5`.
/// Lados sem leitura (`nil` ou `0%`) são ignorados; se os dois limites cruzam no mesmo evento, prevalece o crítico.
struct BatteryAlertPolicy: Sendable {
    private struct SideState: Sendable {
        var firedLow = false
        var firedCritical = false
    }

    private var leftState = SideState()
    private var rightState = SideState()

    mutating func evaluate(state: QCYState, settings: BatteryAlertSettings) -> [BatteryAlert] {
        evaluate(
            left: state.left.flatMap { $0.percent > 0 ? $0 : nil },
            right: state.right.flatMap { $0.percent > 0 ? $0 : nil },
            settings: settings
        )
    }

    mutating func evaluate(
        left: QCYBatteryLevel?,
        right: QCYBatteryLevel?,
        settings: BatteryAlertSettings
    ) -> [BatteryAlert] {
        var alerts: [BatteryAlert] = []
        if let alert = evaluate(side: .left, level: left, settings: settings, state: &leftState) {
            alerts.append(alert)
        }
        if let alert = evaluate(side: .right, level: right, settings: settings, state: &rightState) {
            alerts.append(alert)
        }
        return alerts
    }

    private func evaluate(
        side: BatteryAlertSide,
        level: QCYBatteryLevel?,
        settings: BatteryAlertSettings,
        state: inout SideState
    ) -> BatteryAlert? {
        guard let level, level.percent > 0 else { return nil }

        if level.isCharging {
            state.firedLow = false
            state.firedCritical = false
            return nil
        }

        if level.percent > BatteryAlertSeverity.low.rearmThreshold {
            state.firedLow = false
        }
        if level.percent > BatteryAlertSeverity.critical.rearmThreshold {
            state.firedCritical = false
        }

        let shouldFireCritical = settings.criticalEnabled
            && !state.firedCritical
            && level.percent <= BatteryAlertSeverity.critical.threshold

        if shouldFireCritical {
            state.firedCritical = true
            state.firedLow = true
            return BatteryAlert(side: side, severity: .critical, percent: level.percent)
        }

        let shouldFireLow = settings.lowEnabled
            && !state.firedLow
            && level.percent <= BatteryAlertSeverity.low.threshold

        if shouldFireLow {
            state.firedLow = true
            return BatteryAlert(side: side, severity: .low, percent: level.percent)
        }

        return nil
    }
}
