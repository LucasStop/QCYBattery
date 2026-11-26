import QCYKit

/// O que o fone devolveu de fato: controle ou lado sem leitura fica inativo na interface e não escreve.
extension QCYViewModel {
    var isLDACAvailable: Bool { state.isLDACEnabled != nil }
    var isGameAvailable: Bool { state.isLowLatencyEnabled != nil }
    var isSoundEffectAvailable: Bool { state.soundEffect != nil }
    var isBalanceAvailable: Bool { state.balance != nil }
    var isPowerOffAvailable: Bool { state.powerOff != nil }
    var isToneVolumeAvailable: Bool { state.toneVolume != nil }

    /// Fone fora do ouvido ou no estojo reporta 0%: sem leitura, não bateria vazia.
    var leftLevel: QCYBatteryLevel? { state.left.flatMap { $0.percent > 0 ? $0 : nil } }
    var rightLevel: QCYBatteryLevel? { state.right.flatMap { $0.percent > 0 ? $0 : nil } }
}
