import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Gravador compacto de atalho global de ANC (T16, DESIGN.md): exibe o chip com a combinação gravada e botão de
/// limpar (`×`), ou entra em modo de captura `keyDown` com modificadores dentro da própria linha.
struct QCYGlobalHotKeyRecorder: View {
    let shortcut: MacroKeyShortcut?
    @Binding var isRecording: Bool
    let onRecord: (MacroKeyShortcut) -> Void
    let onClear: () -> Void
    let onMissingModifiers: () -> Void

    @State private var keyMonitor: Any?

    var body: some View {
        HStack(spacing: 4) {
            Button {
                isRecording.toggle()
            } label: {
                Text(displayText)
                    .font(.system(size: 12, weight: isRecording || shortcut != nil ? .medium : .regular))
                    .foregroundStyle(textColor)
                    .lineLimit(1)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityTitle)

            if !isRecording, shortcut != nil {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 2)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("qcy.adjustments.hotkey.clear")
            }
        }
        .padding(.vertical, 5)
        .padding(.leading, 10)
        .padding(.trailing, (!isRecording && shortcut != nil) ? 7 : 10)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    isRecording ? Color.accentColor : Color.primary.opacity(0.18),
                    lineWidth: isRecording ? 1.5 : 1
                )
        )
        .shadow(color: isRecording ? Color.accentColor.opacity(0.22) : .clear, radius: 2)
        .onChange(of: isRecording) { _, recording in
            if recording {
                installKeyMonitor()
            } else {
                removeKeyMonitor()
            }
        }
        .onDisappear {
            isRecording = false
            removeKeyMonitor()
        }
    }

    private var displayText: String {
        if isRecording {
            return String(localized: "qcy.adjustments.hotkey.recording")
        }
        if let shortcut {
            return MacroKeyFormatter.format(shortcut)
        }
        return String(localized: "qcy.adjustments.hotkey.empty")
    }

    private var textColor: Color {
        if isRecording { return .accentColor }
        return shortcut == nil ? .secondary : .primary
    }

    private var accessibilityTitle: String {
        if isRecording {
            return String(localized: "qcy.adjustments.hotkey.recording.a11y")
        }
        if let shortcut {
            let formatted = MacroKeyFormatter.format(shortcut)
            return String(
                format: String(localized: "qcy.adjustments.hotkey.defined.a11y"),
                locale: .current,
                formatted
            )
        }
        return String(localized: "qcy.adjustments.hotkey.empty.a11y")
    }

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            handleKeyEvent(event)
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        let modifiers = Self.modifiers(from: event.modifierFlags)
        if event.keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
            isRecording = false
            return nil
        }
        if MacroKeyFormatter.isModifierOnlyKey(event.keyCode) {
            return nil
        }
        guard !modifiers.isEmpty else {
            onMissingModifiers()
            return nil
        }

        let recorded = MacroKeyShortcut(keyCode: event.keyCode, modifiers: modifiers)
        isRecording = false
        onRecord(recorded)
        return nil
    }

    static func modifiers(from flags: NSEvent.ModifierFlags) -> Set<MacroKeyModifier> {
        var result: Set<MacroKeyModifier> = []
        if flags.contains(.command) { result.insert(.command) }
        if flags.contains(.shift) { result.insert(.shift) }
        if flags.contains(.option) { result.insert(.option) }
        if flags.contains(.control) { result.insert(.control) }
        return result
    }
}
