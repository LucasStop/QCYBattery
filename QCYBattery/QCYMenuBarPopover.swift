import AppKit
import QCYKit
import SwiftUI

/// Popover rápido da barra de menu (T13): bateria L/R, seletor de ANC e atalhos para a janela e saída.
struct QCYMenuBarPopover: View {
    @Bindable var model: QCYViewModel
    let openMainWindow: () -> Void
    let quitApp: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(spacing: 12) {
                batteryGroup
                banner
                controlsGroup
            }
            .padding(12)
            Divider()
            footer
        }
        .frame(width: 320)
    }

    // MARK: - Cabeçalho

    private var header: some View {
        HStack(spacing: 8) {
            headerIcon
            VStack(alignment: .leading, spacing: 1) {
                Text("MeloBuds Pro")
                    .font(.system(size: 13, weight: .semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(badge)
                .font(.caption.weight(.medium))
                .foregroundStyle(badgeColor)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerIcon: some View {
        Group {
            if model.phase == .connected {
                Image("lb.headphones.bluetooth").resizable().scaledToFit()
            } else {
                Image(systemName: "headphones").resizable().scaledToFit()
            }
        }
        .padding(6)
        .frame(width: 28, height: 28)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .accessibilityHidden(true)
    }

    private var subtitle: LocalizedStringKey {
        switch model.phase {
        case .loading: "qcy.status.reading"
        case .connected: "qcy.popover.subtitle.connected"
        case .disconnected: "qcy.status.disconnected"
        }
    }

    private var badge: LocalizedStringKey {
        switch model.phase {
        case .loading: "qcy.badge.reading"
        case .connected: model.isCharging ? "charge.charging" : "qcy.badge.connected"
        case .disconnected: "qcy.badge.none"
        }
    }

    private var badgeColor: Color {
        guard model.phase == .connected else { return .secondary }
        return model.isCharging
            ? Color(light: 0x2B6CB0, dark: 0x63B3ED)
            : BatteryLevel.normal.color
    }

    // MARK: - Bateria

    private var batteryGroup: some View {
        QCYGroup {
            VStack(spacing: 8) {
                HStack {
                    QCYRing(side: "qcy.side.left", level: model.leftLevel, phase: model.phase)
                    QCYRing(side: "qcy.side.right", level: model.rightLevel, phase: model.phase)
                }
                Text(batteryFootnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 12)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)
        }
    }

    private var batteryFootnote: LocalizedStringKey {
        guard model.phase == .connected else { return "qcy.foot.none" }
        return model.isCharging ? "qcy.foot.charging" : "qcy.foot.polling"
    }

    // MARK: - Avisos

    @ViewBuilder
    private var banner: some View {
        if model.writeFailed {
            QCYBanner(
                tint: BatteryLevel.critical.color,
                title: "qcy.error.title",
                detail: "qcy.popover.error.detail",
                action: ("qcy.error.retry", { model.retryAfterFailure() })
            )
            .accessibilityAddTraits(.isModal)
        } else if model.pending != nil {
            QCYBanner(
                tint: Color(light: 0x2B6CB0, dark: 0x63B3ED),
                title: "qcy.pending.title",
                detail: "qcy.popover.pending.detail",
                spinner: true
            )
        } else if model.phase == .disconnected {
            QCYBanner(
                tint: BatteryLevel.low.color,
                title: "qcy.offline.title",
                detail: "qcy.popover.offline.detail",
                action: ("qcy.offline.retry", { model.reconnect() })
            )
        } else if model.isReadOnly, model.phase == .connected {
            QCYBanner(
                tint: Color(light: 0x2B6CB0, dark: 0x63B3ED),
                title: "qcy.readonly.title",
                detail: "qcy.readonly.detail"
            )
        }
    }

    // MARK: - Controles

    private var controlsGroup: some View {
        QCYGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("qcy.anc.title")
                    .font(.system(size: 12, weight: .medium))
                QCYANCSelector(selection: model.ancSelection) { choice in
                    model.select(choice)
                }
            }
            .padding(12)
            .disabled(model.areControlsDisabled)
            .opacity(model.areControlsDisabled && model.pending == nil ? 0.55 : 1)
        }
    }

    // MARK: - Rodapé

    private var footer: some View {
        HStack {
            Button(action: openMainWindow) {
                Text("qcy.menubar.open")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }
            .buttonStyle(.plain)
            Spacer()
            Button(action: quitApp) {
                Text("qcy.menubar.quit")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

#if DEBUG
#Preview("Conectado") {
    QCYMenuBarPopover(model: previewModel(.connected), openMainWindow: {}, quitApp: {})
}
#Preview("Carregando") {
    QCYMenuBarPopover(model: previewModel(.charging), openMainWindow: {}, quitApp: {})
}
#Preview("Sem conexão") {
    QCYMenuBarPopover(model: previewModel(.disconnected), openMainWindow: {}, quitApp: {})
}
#Preview("Somente leitura") {
    QCYMenuBarPopover(model: previewModel(.connected, readOnly: true), openMainWindow: {}, quitApp: {})
}
#endif
