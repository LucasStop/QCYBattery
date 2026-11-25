import Carbon.HIToolbox
import QCYKit
import SwiftUI

/// Formatação determinística de `MacroKeyShortcut` no padrão visual do macOS (`⌃ ⌥ ⇧ ⌘ M`).
enum MacroKeyFormatter {
    private static let modifierKeyCodes: Set<UInt16> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]

    private static let keyNames: [UInt16: String] = [
        UInt16(kVK_ANSI_A): "A", UInt16(kVK_ANSI_B): "B", UInt16(kVK_ANSI_C): "C", UInt16(kVK_ANSI_D): "D",
        UInt16(kVK_ANSI_E): "E", UInt16(kVK_ANSI_F): "F", UInt16(kVK_ANSI_G): "G", UInt16(kVK_ANSI_H): "H",
        UInt16(kVK_ANSI_I): "I", UInt16(kVK_ANSI_J): "J", UInt16(kVK_ANSI_K): "K", UInt16(kVK_ANSI_L): "L",
        UInt16(kVK_ANSI_M): "M", UInt16(kVK_ANSI_N): "N", UInt16(kVK_ANSI_O): "O", UInt16(kVK_ANSI_P): "P",
        UInt16(kVK_ANSI_Q): "Q", UInt16(kVK_ANSI_R): "R", UInt16(kVK_ANSI_S): "S", UInt16(kVK_ANSI_T): "T",
        UInt16(kVK_ANSI_U): "U", UInt16(kVK_ANSI_V): "V", UInt16(kVK_ANSI_W): "W", UInt16(kVK_ANSI_X): "X",
        UInt16(kVK_ANSI_Y): "Y", UInt16(kVK_ANSI_Z): "Z",
        UInt16(kVK_ANSI_0): "0", UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5", UInt16(kVK_ANSI_6): "6", UInt16(kVK_ANSI_7): "7",
        UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=", UInt16(kVK_ANSI_LeftBracket): "[",
        UInt16(kVK_ANSI_RightBracket): "]", UInt16(kVK_ANSI_Backslash): "\\", UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'", UInt16(kVK_ANSI_Comma): ",", UInt16(kVK_ANSI_Period): ".",
        UInt16(kVK_ANSI_Slash): "/", UInt16(kVK_ANSI_Grave): "`",
        UInt16(kVK_Return): "↩", UInt16(kVK_Tab): "⇥", UInt16(kVK_Space): "Space",
        UInt16(kVK_Delete): "⌫", UInt16(kVK_ForwardDelete): "⌦", UInt16(kVK_Escape): "⎋",
        UInt16(kVK_LeftArrow): "←", UInt16(kVK_RightArrow): "→",
        UInt16(kVK_UpArrow): "↑", UInt16(kVK_DownArrow): "↓",
        UInt16(kVK_F1): "F1", UInt16(kVK_F2): "F2", UInt16(kVK_F3): "F3", UInt16(kVK_F4): "F4",
        UInt16(kVK_F5): "F5", UInt16(kVK_F6): "F6", UInt16(kVK_F7): "F7", UInt16(kVK_F8): "F8",
        UInt16(kVK_F9): "F9", UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12"
    ]

    static func isModifierOnlyKey(_ keyCode: UInt16) -> Bool {
        modifierKeyCodes.contains(keyCode)
    }

    static func format(_ shortcut: MacroKeyShortcut) -> String {
        var parts: [String] = []
        if shortcut.modifiers.contains(.control) { parts.append("⌃") }
        if shortcut.modifiers.contains(.option) { parts.append("⌥") }
        if shortcut.modifiers.contains(.shift) { parts.append("⇧") }
        if shortcut.modifiers.contains(.command) { parts.append("⌘") }
        parts.append(keyNames[shortcut.keyCode] ?? "Key \(shortcut.keyCode)")
        return parts.joined(separator: " ")
    }
}

/// Gravador de atalho de teclado no padrão visual do DESIGN.md.
struct MacroKeyRecorderControl: View {
    let shortcut: MacroKeyShortcut?
    let isRecording: Bool
    let onToggleRecording: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggleRecording) {
                HStack {
                    Text(displayText)
                        .font(.system(size: 12, weight: isRecording || shortcut != nil ? .medium : .regular))
                        .foregroundStyle(textColor)
                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isRecording ? Color.accentColor : Color.primary.opacity(0.18),
                            lineWidth: isRecording ? 1.5 : 1
                        )
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("qcy.macro.editor.hotkey.label")

            if shortcut != nil {
                Button(action: onClear) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("qcy.macro.editor.hotkey.clear")
            }
        }
    }

    private var displayText: String {
        if isRecording {
            return String(localized: "qcy.macro.editor.hotkey.recording")
        }
        if let shortcut {
            return MacroKeyFormatter.format(shortcut)
        }
        return String(localized: "qcy.macro.editor.hotkey.empty")
    }

    private var textColor: Color {
        if isRecording { return .accentColor }
        return shortcut == nil ? .secondary : .primary
    }
}

/// Banner compacto com barra lateral colorida reutilizado para avisos e feedback dentro do sheet.
struct MacroNoticeBanner: View {
    let tint: Color
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .padding(.leading, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(alignment: .leading) { Rectangle().fill(tint).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

/// Silhueta vetorial do fone esquerdo ou direito, espelhada no eixo horizontal para o lado R.
struct QCYEarbudGlyph: View {
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

// MARK: - Rótulos localizados compartilhados entre Toques e Editor de Macro

extension MediaCommand {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .play: "qcy.macro.trigger.play"
        case .next: "qcy.macro.trigger.next"
        case .previous: "qcy.macro.trigger.previous"
        }
    }
}

extension MacroEditorModel.ActionKind {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .keyboardShortcut: "qcy.macro.action.keyboardShortcut"
        case .shortcut: "qcy.macro.action.shortcut"
        case .open: "qcy.macro.action.open"
        case .script: "qcy.macro.action.script"
        }
    }
}

extension QCYGesture {
    var formattedDisplayName: String {
        let tap = String(localized: tap.localizedResource)
        let side = String(localized: side.localizedResource)
        return "\(tap) · \(side)"
    }
}

extension QCYGesture.Tap {
    var localizedTitle: LocalizedStringKey {
        switch self {
        case .single: "qcy.touch.tap.single"
        case .double: "qcy.touch.tap.double"
        case .triple: "qcy.touch.tap.triple"
        }
    }

    var localizedResource: LocalizedStringResource {
        switch self {
        case .single: "qcy.touch.tap.single"
        case .double: "qcy.touch.tap.double"
        case .triple: "qcy.touch.tap.triple"
        }
    }
}

extension QCYGesture.Side {
    var localizedResource: LocalizedStringResource {
        switch self {
        case .left: "qcy.side.left"
        case .right: "qcy.side.right"
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

    var localizedResource: LocalizedStringResource {
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
