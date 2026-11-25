#if DEBUG
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
    func send(_ packet: QCYPacket) {}
}

enum PreviewScenario { case connected, charging, loading, disconnected }

@MainActor
func previewModel(_ scenario: PreviewScenario, readOnly: Bool = false) -> QCYViewModel {
    let link = PreviewQCYLink()
    let model = QCYViewModel(link: link, isReadOnly: readOnly)
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
        link.onState?(state)
    case .charging:
        var state = QCYState()
        state.left = QCYBatteryLevel(raw: 0x80 | 84)
        state.right = QCYBatteryLevel(raw: 0x80 | 86)
        state.ancScene = QCYANScene(mode: 0x02, subScene: 0x00, noiseValue: 0x00)
        state.soundEffect = .default
        state.balance = 50
        link.onState?(state)
    case .loading:
        break
    case .disconnected:
        link.onDisconnect?()
    }
    return model
}
#endif
