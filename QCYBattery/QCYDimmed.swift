import SwiftUI

extension View {
    /// Controle sem leitura do fone fica inativo e esmaecido, no mesmo tom do estado desconectado.
    func dimmed(_ isDimmed: Bool) -> some View {
        disabled(isDimmed).opacity(isDimmed ? 0.55 : 1)
    }
}
