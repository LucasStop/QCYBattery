import QCYKit
import SwiftUI

/// Aba Toques da janela principal (T15): desenho dos fones L/R, remapeamento dos 6 gestos medidos (1x, 2x e 3x)
/// e editor de "Macro no Mac" em sheet modal.
struct QCYTouchView: View {
    @Bindable var model: QCYViewModel
    @Bindable var macroStore: MacroStore
    private let macroRunner: MacroRunner

    @State private var editorModel: MacroEditorModel?
    @State private var pendingRemoval: PendingMacroRemoval?
    @State private var showOfflineSavedBanner = false
    @State private var removalFailed = false

    private let labelColumnWidth: CGFloat = 92

    init(
        model: QCYViewModel,
        macroStore: MacroStore? = nil,
        macroRunner: MacroRunner = MacroRunner()
    ) {
        self.model = model
        self.macroStore = macroStore ?? model.macroStore
        self.macroRunner = macroRunner
    }

    var body: some View {
        VStack(spacing: 12) {
            QCYStatusBanner(model: model)
            if showOfflineSavedBanner {
                QCYBanner(
                    tint: Color(light: 0x2B6CB0, dark: 0x63B3ED),
                    title: "qcy.touch.macro.offlineSaved.title",
                    detail: "qcy.touch.macro.offlineSaved.detail",
                    action: ("qcy.touch.macro.offlineSaved.dismiss", { showOfflineSavedBanner = false })
                )
            }
            if removalFailed {
                QCYBanner(
                    tint: BatteryLevel.critical.color,
                    title: "qcy.macro.editor.saveError.title",
                    detail: "qcy.macro.error.persistenceFailed",
                    action: ("qcy.touch.macro.offlineSaved.dismiss", { removalFailed = false })
                )
            }
            gesturesGroup
        }
        .onChange(of: model.phase) { _, newPhase in
            if newPhase == .connected {
                showOfflineSavedBanner = false
            }
        }
        .sheet(item: $editorModel) { editor in
            QCYMacroEditorView(
                model: editor,
                isEarbudsConnected: model.phase == .connected,
                onCancel: { editorModel = nil },
                onSave: { saveEditor(editor) }
            )
        }
        .alert(
            "qcy.touch.macro.removeConfirm.title",
            isPresented: removalAlertBinding,
            presenting: pendingRemoval
        ) { removal in
            Button("qcy.touch.macro.removeConfirm.action", role: .destructive) {
                confirmRemoval(removal)
            }
            Button("qcy.macro.editor.cancel", role: .cancel) {
                pendingRemoval = nil
            }
        } message: { removal in
            Text(removalMessage(for: removal))
        }
    }

    private var removalAlertBinding: Binding<Bool> {
        Binding(
            get: { pendingRemoval != nil },
            set: { isPresented in
                if !isPresented { pendingRemoval = nil }
            }
        )
    }

    private var gesturesGroup: some View {
        let isMenuBlocked = model.isReadOnly || model.pending != nil
        return QCYGroup {
            VStack(spacing: 0) {
                earbudsHeader
                ForEach(QCYGesture.Tap.allCases, id: \.self) { tap in
                    Divider()
                    gestureRow(for: tap)
                }
            }
            .disabled(isMenuBlocked)
            .opacity(model.isReadOnly ? 0.55 : 1)
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
            gestureCell(for: leftGesture, sideKey: "qcy.side.left")
            gestureCell(for: rightGesture, sideKey: "qcy.side.right")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
    }
}

private extension QCYTouchView {
    func gestureCell(for gesture: QCYGesture, sideKey: String) -> some View {
        let macro = macroForGesture(gesture)
        return QCYGestureCell(
            selection: model.keyMap[gesture],
            macro: macro,
            isEarbudsActionDisabled: model.areControlsDisabled,
            accessibilityLabel: cellAccessibilityLabel(tap: gesture.tap, side: sideKey),
            onSelect: { function in
                model.choose(function: function, for: gesture)
            },
            onEditMacro: {
                openMacroEditor(for: gesture)
            },
            onRemoveMacro: {
                if let macro {
                    pendingRemoval = PendingMacroRemoval(gesture: gesture, macro: macro)
                }
            }
        )
    }

    func macroForGesture(_ gesture: QCYGesture) -> Macro? {
        guard let function = model.keyMap[gesture],
              let trigger = MediaCommand(keyFunction: function) else {
            return nil
        }
        return macroStore.macro(for: trigger)
    }

    func openMacroEditor(for gesture: QCYGesture) {
        editorModel = MacroEditorModel(
            targetGesture: gesture,
            store: macroStore,
            keyMap: model.keyMap,
            runner: macroRunner
        )
    }

    func saveEditor(_ editor: MacroEditorModel) {
        do {
            let outcome = try editor.save(isEarbudsConnected: model.phase == .connected) { function, gesture in
                model.choose(function: function, for: gesture)
            }
            guard let outcome else { return }
            editorModel = nil
            switch outcome {
            case .savedAndApplied:
                showOfflineSavedBanner = false
            case .savedOffline:
                showOfflineSavedBanner = true
            }
        } catch {
            // `editor.saveError` já exibe a falha dentro do sheet.
        }
    }

    func confirmRemoval(_ removal: PendingMacroRemoval) {
        pendingRemoval = nil
        do {
            try macroStore.remove(id: removal.macro.id)
            removalFailed = false
            if model.phase == .connected, !model.isReadOnly {
                model.choose(function: .unassigned, for: removal.gesture)
            }
        } catch {
            removalFailed = true
        }
    }

    func removalMessage(for removal: PendingMacroRemoval) -> String {
        let shared = model.otherGestures(sharing: removal.macro.trigger, excluding: removal.gesture)
        if shared.isEmpty {
            return String(
                format: String(localized: "qcy.touch.macro.removeConfirm.message"),
                locale: .current,
                removal.macro.name
            )
        }
        let others = shared.map(\.formattedDisplayName).joined(separator: ", ")
        return String(
            format: String(localized: "qcy.touch.macro.removeConfirm.sharedMessage"),
            locale: .current,
            removal.macro.name,
            others
        )
    }

    func cellAccessibilityLabel(tap: QCYGesture.Tap, side: String) -> Text {
        Text(tap.localizedTitle) + Text(", ") + Text(LocalizedStringKey(side))
    }
}

private struct PendingMacroRemoval {
    let gesture: QCYGesture
    let macro: Macro
}

// MARK: - Célula de gesto

/// Menu nativo por lado (`L` / `R`) com as 9 funções de `QCYKeyFunction`, "Macro no Mac…" e "Remover macro".
struct QCYGestureCell: View {
    let selection: QCYKeyFunction?
    let macro: Macro?
    let isEarbudsActionDisabled: Bool
    let accessibilityLabel: Text
    let onSelect: (QCYKeyFunction) -> Void
    let onEditMacro: () -> Void
    let onRemoveMacro: () -> Void

    var body: some View {
        Menu {
            ForEach(QCYKeyFunction.allCases, id: \.self) { function in
                Button {
                    onSelect(function)
                } label: {
                    if macro == nil, selection == function {
                        Label(function.localizedTitle, systemImage: "checkmark")
                    } else {
                        Text(function.localizedTitle)
                    }
                }
                .disabled(isEarbudsActionDisabled)
            }
            Divider()
            Button(action: onEditMacro) {
                if macro != nil {
                    Label("qcy.touch.macro.menuItem", systemImage: "checkmark")
                } else {
                    Text("qcy.touch.macro.menuItem")
                }
            }
            if macro != nil {
                Button("qcy.touch.macro.remove", role: .destructive, action: onRemoveMacro)
            }
        } label: {
            cellLabel
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(accessibilityValueText)
    }

    private var cellLabel: some View {
        let hasMacro = macro != nil
        return HStack(spacing: 4) {
            Text(displayText)
                .font(.system(size: 12, weight: hasMacro ? .medium : .regular))
                .foregroundStyle(textColor)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 4)
            Image(systemName: "chevron.down")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(hasMacro ? Color.accentColor : Color.secondary)
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, minHeight: 26, alignment: .leading)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 6, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    hasMacro ? Color.accentColor : Color.primary.opacity(0.18),
                    lineWidth: 1
                )
        )
    }

    private var displayText: String {
        if let macro {
            return String(format: String(localized: "qcy.touch.macro.cell"), locale: .current, macro.name)
        }
        if let selection {
            return String(localized: selection.localizedResource)
        }
        return "—"
    }

    private var textColor: Color {
        if macro != nil { return .accentColor }
        return selection == nil ? .secondary : .primary
    }

    private var accessibilityValueText: Text {
        Text(displayText)
    }
}

// MARK: - Desenho dos fones

#if DEBUG
#Preview("Aba Toques — com macro") {
    let store = previewMacroStore(macros: [
        Macro(name: "Mudo", trigger: .play, action: .keyboardShortcut(keyCode: 46, modifiers: [.command, .shift]))
    ])
    return QCYTouchView(
        model: previewModel(.connected, macroStore: store),
        macroStore: store,
        macroRunner: previewMacroRunner()
    )
    .padding(16)
    .frame(width: 468)
}

#Preview("Aba Toques — conectado") {
    QCYTouchView(model: previewModel(.connected), macroRunner: previewMacroRunner())
        .padding(16).frame(width: 468)
}

#Preview("Aba Toques — somente leitura") {
    QCYTouchView(model: previewModel(.connected, readOnly: true), macroRunner: previewMacroRunner())
        .padding(16).frame(width: 468)
}

#Preview("Aba Toques — sem conexão") {
    QCYTouchView(model: previewModel(.disconnected), macroRunner: previewMacroRunner())
        .padding(16).frame(width: 468)
}
#endif
