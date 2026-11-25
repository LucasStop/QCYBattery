import AppKit
import QCYKit
import SwiftUI

/// Editor de macro no Mac em sheet modal sobre a janela principal (T15, US-08).
struct QCYMacroEditorView: View {
    @Bindable var model: MacroEditorModel
    let isEarbudsConnected: Bool
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    nameField
                    triggerField
                    triggerWarnings
                    actionKindField
                    actionValueSection
                    feedbackSection
                }
                .padding(16)
            }
            Divider()
            footer
        }
        .frame(width: 420)
        .frame(minHeight: 340, maxHeight: 580)
        .onChange(of: model.isRecordingShortcut) { _, isRecording in
            if isRecording {
                installKeyMonitor()
            } else {
                removeKeyMonitor()
            }
        }
        .onDisappear {
            model.isRecordingShortcut = false
            removeKeyMonitor()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("qcy.macro.editor.title")
                .font(.system(size: 14, weight: .semibold))
            Text(gestureSubtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    private var gestureSubtitle: String {
        let tap = String(localized: model.targetGesture.tap.localizedResource)
        let side = String(localized: model.targetGesture.side.localizedResource)
        return String(format: String(localized: "qcy.macro.editor.subtitle"), locale: .current, tap, side)
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("qcy.macro.editor.name.label")
                .font(.system(size: 12, weight: .medium))
            TextField("qcy.macro.editor.name.placeholder", text: $model.name)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("qcy.macro.editor.name.label")
        }
    }

    private var triggerField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("qcy.macro.editor.trigger.label")
                .font(.system(size: 12, weight: .medium))
            Picker("qcy.macro.editor.trigger.label", selection: $model.trigger) {
                ForEach(MediaCommand.allCases, id: \.self) { command in
                    Text(command.localizedTitle).tag(command)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("qcy.macro.editor.trigger.label")
            Text(sacrificeCaption)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sacrificeCaption: String {
        let functionTitle = String(localized: model.trigger.keyFunction.localizedResource)
        return String(format: String(localized: "qcy.macro.editor.trigger.sacrifice"), locale: .current, functionTitle)
    }

    @ViewBuilder
    private var triggerWarnings: some View {
        if let existing = model.conflictingMacro {
            MacroNoticeBanner(
                tint: BatteryLevel.low.color,
                title: String(localized: "qcy.macro.editor.replace.title"),
                detail: String(
                    format: String(localized: "qcy.macro.editor.replace.detail"),
                    locale: .current,
                    existing.name
                )
            )
        }
        if !model.sharedGestures.isEmpty {
            let names = model.sharedGestures.map(\.formattedDisplayName).joined(separator: ", ")
            let functionTitle = String(localized: model.trigger.keyFunction.localizedResource)
            MacroNoticeBanner(
                tint: Color(light: 0x2B6CB0, dark: 0x63B3ED),
                title: String(localized: "qcy.macro.editor.shared.title"),
                detail: String(
                    format: String(localized: "qcy.macro.editor.shared.detail"),
                    locale: .current,
                    names,
                    functionTitle
                )
            )
        }
        if !isEarbudsConnected {
            MacroNoticeBanner(
                tint: Color(light: 0x2B6CB0, dark: 0x63B3ED),
                title: String(localized: "qcy.macro.editor.offline.title"),
                detail: String(localized: "qcy.macro.editor.offline.detail")
            )
        }
    }

    private var actionKindField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("qcy.macro.editor.actionKind.label")
                .font(.system(size: 12, weight: .medium))
            Picker("qcy.macro.editor.actionKind.label", selection: $model.actionKind) {
                ForEach(MacroEditorModel.ActionKind.allCases, id: \.self) { kind in
                    Text(kind.localizedTitle).tag(kind)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityLabel("qcy.macro.editor.actionKind.label")
        }
    }

    @ViewBuilder
    private var actionValueSection: some View {
        switch model.actionKind {
        case .keyboardShortcut:
            keyboardShortcutField
        case .shortcut:
            shortcutField
        case .open:
            openTargetField
        case .script:
            scriptField
        }
    }
}

// MARK: - Campos por tipo, feedback e rodapé

private extension QCYMacroEditorView {
    var keyboardShortcutField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("qcy.macro.editor.hotkey.label")
                .font(.system(size: 12, weight: .medium))
            MacroKeyRecorderControl(
                shortcut: model.keyShortcut,
                isRecording: model.isRecordingShortcut,
                onToggleRecording: { model.toggleShortcutRecording() },
                onClear: { model.clearKeyShortcut() }
            )
            Text("qcy.macro.editor.hotkey.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var shortcutField: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("qcy.macro.editor.shortcut.label")
                .font(.system(size: 12, weight: .medium))
            TextField("qcy.macro.editor.shortcut.placeholder", text: $model.shortcutName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("qcy.macro.editor.shortcut.label")
            Text("qcy.macro.editor.shortcut.hint")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    var openTargetField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("qcy.macro.editor.open.kind", selection: $model.openKind) {
                Text("qcy.macro.editor.open.app").tag(MacroEditorModel.OpenKind.app)
                Text("qcy.macro.editor.open.url").tag(MacroEditorModel.OpenKind.url)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text(model.openKind == .app ? "qcy.macro.editor.open.app.label" : "qcy.macro.editor.open.url.label")
                    .font(.system(size: 12, weight: .medium))
                TextField(
                    model.openKind == .app
                        ? "qcy.macro.editor.open.app.placeholder"
                        : "qcy.macro.editor.open.url.placeholder",
                    text: $model.openValue
                )
                .textFieldStyle(.roundedBorder)
                if model.isURLMissingScheme {
                    Text("qcy.macro.editor.open.url.invalid")
                        .font(.caption)
                        .foregroundStyle(BatteryLevel.critical.color)
                } else {
                    Text(model.openKind == .app ? "qcy.macro.editor.open.app.hint" : "qcy.macro.editor.open.url.hint")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    var scriptField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("qcy.macro.editor.script.kind", selection: $model.scriptKind) {
                Text("qcy.macro.editor.script.shell").tag(MacroScriptKind.shell)
                Text("qcy.macro.editor.script.appleScript").tag(MacroScriptKind.appleScript)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            VStack(alignment: .leading, spacing: 4) {
                Text("qcy.macro.editor.script.label")
                    .font(.system(size: 12, weight: .medium))
                TextEditor(text: $model.scriptSource)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 88, maxHeight: 140)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.primary.opacity(0.16), lineWidth: 1)
                    )
                    .accessibilityLabel("qcy.macro.editor.script.label")
            }

            MacroNoticeBanner(
                tint: BatteryLevel.low.color,
                title: String(localized: "qcy.macro.editor.script.warning.title"),
                detail: String(localized: "qcy.macro.editor.script.warning.detail")
            )
        }
    }

    @ViewBuilder
    var feedbackSection: some View {
        if let outcome = model.testOutcome {
            switch outcome {
            case .succeeded:
                MacroNoticeBanner(
                    tint: BatteryLevel.normal.color,
                    title: String(localized: "qcy.macro.editor.test.ok.title"),
                    detail: String(localized: "qcy.macro.editor.test.ok.detail")
                )
            case .failed(let error):
                MacroNoticeBanner(
                    tint: BatteryLevel.critical.color,
                    title: String(localized: "qcy.macro.editor.test.error.title"),
                    detail: error.errorDescription ?? String(localized: "qcy.macro.error.launchFailed")
                )
            }
        }
        if let saveError = model.saveError {
            MacroNoticeBanner(
                tint: BatteryLevel.critical.color,
                title: String(localized: "qcy.macro.editor.saveError.title"),
                detail: saveError.errorDescription ?? String(localized: "qcy.macro.error.persistenceFailed")
            )
        }
    }

    var footer: some View {
        HStack {
            Button {
                Task { await model.testMacro() }
            } label: {
                HStack(spacing: 6) {
                    if model.isTesting {
                        ProgressView().controlSize(.small)
                    }
                    Text("qcy.macro.editor.test")
                }
            }
            .disabled(!model.canTest)

            Spacer()

            Button("qcy.macro.editor.cancel", action: onCancel)
            Button("qcy.macro.editor.save", action: onSave)
                .buttonStyle(.borderedProminent)
                .disabled(!model.canSave)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.regularMaterial)
    }

    func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = Self.macroModifiers(from: event.modifierFlags)
            let handled = model.recordKey(keyCode: event.keyCode, modifiers: modifiers)
            return handled ? nil : event
        }
    }

    func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    static func macroModifiers(from flags: NSEvent.ModifierFlags) -> Set<MacroKeyModifier> {
        var result: Set<MacroKeyModifier> = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }
}

#if DEBUG
#Preview("Editor de macro — script") {
    let store = previewMacroStore()
    let editor = MacroEditorModel(
        targetGesture: .leftTripleTap,
        store: store,
        keyMap: [.leftTripleTap: .playPause, .rightSingleTap: .playPause],
        runner: previewMacroRunner()
    )
    editor.name = "Silenciar mic"
    editor.actionKind = .script
    editor.scriptSource = "~/Scripts/toggle-mic.sh"
    return QCYMacroEditorView(
        model: editor,
        isEarbudsConnected: true,
        onCancel: {},
        onSave: {}
    )
}

#Preview("Editor de macro — atalho de teclado") {
    let store = previewMacroStore()
    let editor = MacroEditorModel(
        targetGesture: .rightDoubleTap,
        store: store,
        keyMap: [.rightDoubleTap: .nextTrack],
        runner: previewMacroRunner()
    )
    editor.name = "Mudo"
    editor.actionKind = .keyboardShortcut
    editor.keyShortcut = MacroKeyShortcut(keyCode: 46, modifiers: [.command, .shift])
    return QCYMacroEditorView(
        model: editor,
        isEarbudsConnected: true,
        onCancel: {},
        onSave: {}
    )
}
#endif
