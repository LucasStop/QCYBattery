import QCYKit
import SwiftUI

/// Aba Toques da janela principal (T15): desenho dos fones L/R e remapeamento dos 6 gestos medidos (1x, 2x e 3x).
struct QCYTouchView: View {
    @Bindable var model: QCYViewModel

    private let labelColumnWidth: CGFloat = 92

    var body: some View {
        VStack(spacing: 12) {
            QCYStatusBanner(model: model)
            gesturesGroup
        }
    }

    private var gesturesGroup: some View {
        QCYGroup {
            VStack(spacing: 0) {
                earbudsHeader
                ForEach(QCYGesture.Tap.allCases, id: \.self) { tap in
                    Divider()
                    gestureRow(for: tap)
                }
            }
            .disabled(model.areControlsDisabled)
            .opacity(model.areControlsDisabled && model.pending == nil ? 0.55 : 1)
        }
    }

    private var earbudsHeader: some View {
        HStack(spacing: 8) {
            Text("qcy.touch.header.gesture")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: labelColumnWidth, alignment: .leading)
            earbudColumn(side: .left, title: "qcy.side.left", badge: "L")
            earbudColumn(side: .right, title: "qcy.side.right", badge: "R")
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
    }

    private func earbudColumn(side: QCYGesture.Side, title: LocalizedStringKey, badge: String) -> some View {
        VStack(spacing: 4) {
            QCYEarbudGlyph(side: side)
                .frame(width: 40, height: 44)
                .foregroundStyle(.primary)
                .accessibilityHidden(true)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(badge)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func gestureRow(for tap: QCYGesture.Tap) -> some View {
        let leftGesture = QCYGesture(side: .left, tap: tap)
        let rightGesture = QCYGesture(side: .right, tap: tap)

        return HStack(spacing: 8) {
            Text(tap.localizedTitle)
                .font(.system(size: 12, weight: .medium))
                .frame(width: labelColumnWidth, alignment: .leading)
            QCYGestureCell(
                selection: model.keyMap[leftGesture],
                accessibilityLabel: cellAccessibilityLabel(tap: tap, side: "qcy.side.left")
            ) { function in
                model.choose(function: function, for: leftGesture)
            }
            QCYGestureCell(
                selection: model.keyMap[rightGesture],
                accessibilityLabel: cellAccessibilityLabel(tap: tap, side: "qcy.side.right")
            ) { function in
                model.choose(function: function, for: rightGesture)
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }

    private func cellAccessibilityLabel(tap: QCYGesture.Tap, side: String) -> Text {
        Text(tap.localizedTitle) + Text(", ") + Text(LocalizedStringKey(side))
    }
}

// MARK: - Célula de gesto

/// Menu nativo por lado (`L` / `R`) com as 9 funções de `QCYKeyFunction` (DESIGN.md).
struct QCYGestureCell: View {
    let selection: QCYKeyFunction?
    let accessibilityLabel: Text
    let onSelect: (QCYKeyFunction) -> Void

    var body: some View {
        Picker(selection: binding) {
            if selection == nil {
                Text("—").tag(Optional<QCYKeyFunction>.none)
            }
            ForEach(QCYKeyFunction.allCases, id: \.self) { function in
                Text(function.localizedTitle).tag(Optional(function))
            }
        } label: {
            accessibilityLabel
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .frame(maxWidth: .infinity)
        .accessibilityLabel(accessibilityLabel)
    }

    private var binding: Binding<QCYKeyFunction?> {
        Binding(
            get: { selection },
            set: { newValue in
                if let newValue {
                    onSelect(newValue)
                }
            }
        )
    }
}

// MARK: - Desenho dos fones

/// Silhueta vetorial do fone esquerdo ou direito, espelhada no eixo horizontal para o lado R.
private struct QCYEarbudGlyph: View {
    let side: QCYGesture.Side

    var body: some View {
        QCYEarbudShape()
            .stroke(style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            .scaleEffect(x: side == .right ? -1 : 1, y: 1)
    }
}

private struct QCYEarbudShape: Shape {
    func path(in rect: CGRect) -> Path {
        let scaleX = rect.width / 40
        let scaleY = rect.height / 44
        func point(_ posX: CGFloat, _ posY: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + posX * scaleX, y: rect.minY + posY * scaleY)
        }

        var path = Path()
        path.move(to: point(16, 10))
        path.addCurve(to: point(7, 18.5), control1: point(11, 10), control2: point(7, 13.6))
        path.addCurve(to: point(14, 26.9), control1: point(7, 22.9), control2: point(10, 26.3))
        path.addLine(to: point(14, 35))
        path.addCurve(to: point(20, 35), control1: point(14, 39), control2: point(20, 39))
        path.addLine(to: point(20, 20.5))
        path.addCurve(to: point(24, 16), control1: point(20, 18), control2: point(21.8, 16.5))
        path.addCurve(to: point(27, 12.8), control1: point(25.8, 15.6), control2: point(27, 14.3))
        path.addCurve(to: point(23.6, 10), control1: point(27, 11.2), control2: point(25.6, 10))
        path.closeSubpath()

        let dotRect = CGRect(
            x: rect.minX + 12.8 * scaleX,
            y: rect.minY + 16.3 * scaleY,
            width: 4.4 * scaleX,
            height: 4.4 * scaleY
        )
        path.addEllipse(in: dotRect)
        return path
    }
}

// MARK: - Rótulos localizados

extension QCYGesture.Tap {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .single: "qcy.touch.tap.single"
        case .double: "qcy.touch.tap.double"
        case .triple: "qcy.touch.tap.triple"
        }
    }
}

extension QCYKeyFunction {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .unassigned: "qcy.touch.function.unassigned"
        case .playPause: "qcy.touch.function.playPause"
        case .previousTrack: "qcy.touch.function.previousTrack"
        case .nextTrack: "qcy.touch.function.nextTrack"
        case .voiceAssistant: "qcy.touch.function.voiceAssistant"
        case .volumeUp: "qcy.touch.function.volumeUp"
        case .volumeDown: "qcy.touch.function.volumeDown"
        case .lowLatency: "qcy.touch.function.lowLatency"
        case .ancMode: "qcy.touch.function.ancMode"
        }
    }
}

#if DEBUG
#Preview("Aba Toques — conectado") {
    QCYTouchView(model: previewModel(.connected))
        .padding(16)
        .frame(width: 468)
}
#Preview("Aba Toques — somente leitura") {
    QCYTouchView(model: previewModel(.connected, readOnly: true))
        .padding(16)
        .frame(width: 468)
}
#Preview("Aba Toques — sem conexão") {
    QCYTouchView(model: previewModel(.disconnected))
        .padding(16)
        .frame(width: 468)
}
#endif
