import AppKit
import SwiftUI

extension View {
    /// Controle sem leitura do fone fica inativo e esmaecido, no mesmo tom do estado desconectado.
    func dimmed(_ isDimmed: Bool) -> some View {
        disabled(isDimmed).opacity(isDimmed ? 0.55 : 1)
    }
}

/// Fone com o selo de Bluetooth quando conectado, símbolo do sistema quando não. `.font` explícito: sem ele o
/// símbolo `lb.*` não desenha na janela nem no popover (mesma regra do LogiBattery, #77).
struct HeadphonesIcon: View {
    let isConnected: Bool
    let size: CGFloat

    var body: some View {
        if isConnected {
            Image("lb.headphones.bluetooth").font(.system(size: size))
        } else {
            Image(systemName: "headphones").font(.system(size: size))
        }
    }
}

/// O rótulo do `MenuBarExtra` vira imagem do item de status e descarta o símbolo do catálogo: rasteriza o símbolo
/// aqui, em `NSImage` template (o macOS tinge conforme o tema da barra).
struct MenuBarHeadphonesIcon: View {
    let isConnected: Bool

    var body: some View {
        Image(nsImage: Self.image(isConnected: isConnected))
    }

    private static func image(isConnected: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let base = isConnected
            ? NSImage(named: "lb.headphones.bluetooth")
            : NSImage(systemSymbolName: "headphones", accessibilityDescription: nil)
        let image = base?.withSymbolConfiguration(configuration) ?? NSImage()
        image.isTemplate = true
        return image
    }
}
