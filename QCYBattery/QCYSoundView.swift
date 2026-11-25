import QCYKit
import SwiftUI

/// Aba Som da janela principal (T14): grade 2×2 de efeitos medidos, voz reforçada na transparência e balanço L/R.
struct QCYSoundView: View {
    @Bindable var model: QCYViewModel

    var body: some View {
        VStack(spacing: 12) {
            QCYStatusBanner(model: model)
            effectsGroup
            audioControlsGroup
        }
    }

    // MARK: - Efeitos de som

    private var effectsGroup: some View {
        QCYGroup {
            VStack(alignment: .leading, spacing: 10) {
                Text("qcy.sound.effects.title")
                    .font(.system(size: 13, weight: .semibold))
                QCYSoundEffectGrid(selection: model.soundEffect) { effect in
                    model.choose(effect: effect)
                }
                HStack {
                    Spacer()
                    Text("qcy.sound.effects.footer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .disabled(model.areControlsDisabled)
            .opacity(model.areControlsDisabled && model.pending == nil ? 0.55 : 1)
        }
    }

    // MARK: - Voz reforçada e balanço

    private var audioControlsGroup: some View {
        QCYGroup {
            VStack(spacing: 0) {
                vocalBoostRow
                Divider()
                QCYBalanceSlider(
                    balance: model.balance,
                    isDisabled: model.areControlsDisabled,
                    onCommit: { model.setBalance($0) }
                )
                .padding(12)
                .disabled(model.areControlsDisabled)
                .opacity(model.areControlsDisabled && model.pending == nil ? 0.55 : 1)
            }
        }
    }

    private var vocalBoostRow: some View {
        let isRowDisabled = model.areControlsDisabled || !model.isVocalBoostAvailable
        let hint: LocalizedStringKey = model.isVocalBoostAvailable
            ? "qcy.sound.vocal.hint"
            : "qcy.sound.vocal.unavailable"

        return HStack {
            QCYLabel(title: "qcy.sound.vocal.title", hint: hint)
            Spacer()
            Toggle(
                "qcy.sound.vocal.title",
                isOn: Binding(get: { model.isVocalBoostOn }, set: { model.setVocalBoost($0) })
            )
            .labelsHidden()
            .toggleStyle(.switch)
        }
        .padding(12)
        .disabled(isRowDisabled)
        .opacity((model.areControlsDisabled && model.pending == nil) || !model.isVocalBoostAvailable ? 0.55 : 1)
    }
}

// MARK: - Grade de efeitos de som

/// Grade 2×2 dos 4 efeitos medidos no QCYKit (DESIGN.md).
struct QCYSoundEffectGrid: View {
    private struct Item: Identifiable {
        let effect: QCYSoundEffect
        let title: LocalizedStringKey
        let subtitle: LocalizedStringKey
        let symbol: String

        var id: QCYSoundEffect { effect }
    }

    private static let items: [Item] = [
        Item(effect: .spatial, title: "qcy.sound.effect.spatial",
             subtitle: "qcy.sound.effect.spatial.hint", symbol: "dot.radiowaves.left.and.right"),
        Item(effect: .default, title: "qcy.sound.effect.default",
             subtitle: "qcy.sound.effect.default.hint", symbol: "waveform"),
        Item(effect: .pop, title: "qcy.sound.effect.pop",
             subtitle: "qcy.sound.effect.pop.hint", symbol: "chart.bar.fill"),
        Item(effect: .heavyBass, title: "qcy.sound.effect.heavyBass",
             subtitle: "qcy.sound.effect.heavyBass.hint", symbol: "record.circle")
    ]

    let selection: QCYSoundEffect?
    let onSelect: (QCYSoundEffect) -> Void

    private let columns = [
        GridItem(.flexible(), spacing: 8),
        GridItem(.flexible(), spacing: 8)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Self.items) { item in
                let isSelected = selection == item.effect
                Button {
                    onSelect(item.effect)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(isSelected ? Color.white : Color.secondary)
                            .frame(width: 28, height: 28)
                            .background(
                                isSelected ? Color.white.opacity(0.18) : Color(nsColor: .controlBackgroundColor),
                                in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                            )
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title)
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(isSelected ? Color.white : Color.primary)
                            Text(item.subtitle)
                                .font(.system(size: 11))
                                .foregroundStyle(isSelected ? Color.white.opacity(0.85) : Color.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        isSelected ? Color.accentColor : Color.primary.opacity(0.04),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: 1)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("qcy.sound.effects.title")
    }
}

// MARK: - Slider de balanço

/// Slider de balanço L/R (0...100, centro 50) que só envia ao fone ao soltar (DESIGN.md).
struct QCYBalanceSlider: View {
    let balance: UInt8
    let isDisabled: Bool
    let onCommit: (UInt8) -> Void

    @State private var draft: Double
    @State private var isDragging = false

    init(balance: UInt8, isDisabled: Bool, onCommit: @escaping (UInt8) -> Void) {
        self.balance = balance
        self.isDisabled = isDisabled
        self.onCommit = onCommit
        _draft = State(initialValue: Double(min(balance, 100)))
    }

    private var displayedValue: UInt8 {
        UInt8(min(max(draft.rounded(), 0), 100))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                QCYLabel(title: "qcy.sound.balance.title", hint: "qcy.sound.balance.hint")
                Spacer()
                valueText
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("qcy.sound.balance.reset") {
                    draft = 50
                    onCommit(50)
                }
                .controlSize(.small)
                .disabled(isDisabled || displayedValue == 50)
            }

            HStack(spacing: 8) {
                Text("L100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .leading)
                Slider(value: $draft, in: 0...100, step: 1) {
                    Text("qcy.sound.balance.title")
                } onEditingChanged: { editing in
                    isDragging = editing
                    if !editing {
                        onCommit(displayedValue)
                    }
                }
                .labelsHidden()
                Text("R100")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }
        }
        .onChange(of: balance) { _, newValue in
            if !isDragging {
                draft = Double(min(newValue, 100))
            }
        }
    }

    @ViewBuilder
    private var valueText: some View {
        if let offset = Self.formattedOffset(for: displayedValue) {
            Text(offset)
        } else {
            Text("qcy.sound.balance.center")
        }
    }

    /// Formata desvios do centro (`50` devolve `nil`, exibido como `"Centro"`): `"L n"` / `"R n"` com `n = |v-50|*2`.
    static func formattedOffset(for value: UInt8) -> String? {
        let clamped = min(value, 100)
        if clamped == 50 { return nil }
        if clamped < 50 {
            return "L \((50 - Int(clamped)) * 2)"
        }
        return "R \((Int(clamped) - 50) * 2)"
    }
}

#if DEBUG
#Preview("Aba Som — conectado") {
    QCYSoundView(model: previewModel(.connected))
        .padding(16)
        .frame(width: 468)
}
#Preview("Aba Som — fora da transparência") {
    QCYSoundView(model: previewModel(.charging))
        .padding(16)
        .frame(width: 468)
}
#Preview("Aba Som — somente leitura") {
    QCYSoundView(model: previewModel(.connected, readOnly: true))
        .padding(16)
        .frame(width: 468)
}
#Preview("Aba Som — sem conexão") {
    QCYSoundView(model: previewModel(.disconnected))
        .padding(16)
        .frame(width: 468)
}
#endif
