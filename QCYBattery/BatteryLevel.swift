import AppKit
import SwiftUI

/// Faixa de bateria e cor dos anéis. Mesmos limites e cores do LogiBattery (`DESIGN.md`), copiados para o app não
/// depender do código dele.
enum BatteryLevel: Equatable, Sendable {
    case normal, low, critical, unknown

    init(percent: Int?, low: Int = 20, critical: Int = 10) {
        switch percent {
        case nil: self = .unknown
        case let value? where value < critical: self = .critical
        case let value? where value < low: self = .low
        default: self = .normal
        }
    }

    var color: Color {
        switch self {
        case .normal: Color(light: 0x1F9D55, dark: 0x34C77B)
        case .low: Color(light: 0xB7791F, dark: 0xF2B13C)
        case .critical: Color(light: 0xC53030, dark: 0xFF6B6B)
        case .unknown: .secondary
        }
    }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}
