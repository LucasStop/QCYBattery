import Foundation
import QCYKit

/// Cena de ANC que a tela oferece. O `0x17` é a única via de escrita (o `0x0C` não responde no MeloBuds Pro);
/// os bytes são os medidos em `docs/QCY.md` §5.
enum QCYANCChoice: String, CaseIterable, Codable, Equatable, Hashable, Sendable {
    case anc, normal, transparency

    /// Ordem do ciclo do atalho global (US-10): ANC -> Transparência -> Normal -> ANC.
    var nextInCycle: QCYANCChoice {
        switch self {
        case .anc: .transparency
        case .transparency: .normal
        case .normal: .anc
        }
    }

    var packet: QCYPacket {
        switch self {
        case .anc: .ancSetting(mode: 0x01, subScene: 0x02, noiseValue: 0x03)
        case .normal: .ancSetting(mode: 0x02, subScene: 0x00, noiseValue: 0x00)
        case .transparency: .ancSetting(mode: 0x03, subScene: 0x02, noiseValue: 0x00)
        }
    }

    init?(scene: QCYANScene) {
        switch scene.mode {
        case 0x01: self = .anc
        case 0x02: self = .normal
        case 0x03: self = .transparency
        default: return nil
        }
    }
}
