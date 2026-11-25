import Carbon.HIToolbox
import Foundation
import Observation
import QCYKit

/// Desfecho do salvamento no editor de macro.
enum MacroSaveOutcome: Equatable, Sendable {
    case savedAndApplied(Macro)
    case savedOffline(Macro)
}

/// Estado e validação testáveis do editor de macro em sheet (T15, US-08).
@MainActor
@Observable
final class MacroEditorModel: Identifiable {
    enum ActionKind: String, CaseIterable, Equatable, Hashable, Sendable {
        case keyboardShortcut
        case shortcut
        case open
        case script
    }

    enum OpenKind: String, CaseIterable, Equatable, Hashable, Sendable {
        case app
        case url
    }

    let id = UUID()
    let targetGesture: QCYGesture
    let editingMacroID: UUID?

    var name: String = ""
    var trigger: MediaCommand
    var actionKind: ActionKind = .keyboardShortcut {
        didSet {
            if actionKind != oldValue {
                isRecordingShortcut = false
                testOutcome = nil
                saveError = nil
            }
        }
    }
    var keyShortcut: MacroKeyShortcut? {
        didSet { testOutcome = nil }
    }
    var isRecordingShortcut = false
    var shortcutName: String = "" {
        didSet { testOutcome = nil }
    }
    var openKind: OpenKind = .app {
        didSet { testOutcome = nil }
    }
    var openValue: String = "" {
        didSet { testOutcome = nil }
    }
    var scriptKind: MacroScriptKind = .shell {
        didSet { testOutcome = nil }
    }
    var scriptSource: String = "" {
        didSet { testOutcome = nil }
    }

    private(set) var isTesting = false
    private(set) var testOutcome: MacroRunOutcome?
    private(set) var saveError: MacroStoreError?

    @ObservationIgnored private let store: MacroStore
    @ObservationIgnored private let keyMap: [QCYGesture: QCYKeyFunction]
    @ObservationIgnored private let runner: MacroRunner
    @ObservationIgnored private let draftID = UUID()

    init(
        targetGesture: QCYGesture,
        store: MacroStore,
        keyMap: [QCYGesture: QCYKeyFunction],
        runner: MacroRunner = MacroRunner()
    ) {
        self.targetGesture = targetGesture
        self.store = store
        self.keyMap = keyMap
        self.runner = runner

        let existing = Self.existingMacro(for: targetGesture, keyMap: keyMap, store: store)
        self.editingMacroID = existing?.id
        self.trigger = existing?.trigger ?? Self.defaultTrigger(for: targetGesture, keyMap: keyMap, store: store)

        if let existing {
            self.name = existing.name
            load(action: existing.action)
        }
    }

    // MARK: - Avisos derivados

    /// Outra macro já cadastrada no `trigger` escolhido que será substituída ao salvar.
    var conflictingMacro: Macro? {
        guard let existing = store.macro(for: trigger), existing.id != editingMacroID else {
            return nil
        }
        return existing
    }

    /// Outros gestos no fone que usam a mesma função de sacrifício do `trigger` selecionado.
    var sharedGestures: [QCYGesture] {
        QCYGesture.allOrdered.filter { candidate in
            candidate != targetGesture && keyMap[candidate] == trigger.keyFunction
        }
    }

    // MARK: - Validação

    var isNameValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var isURLMissingScheme: Bool {
        guard actionKind == .open, openKind == .url else { return false }
        let trimmed = openValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        return Self.validatedURL(from: trimmed) == nil
    }

    var isActionValid: Bool {
        buildAction() != nil
    }

    var canSave: Bool {
        isNameValid && isActionValid
    }

    var canTest: Bool {
        isActionValid && !isTesting
    }

    // MARK: - Gravação de atalho

    func toggleShortcutRecording() {
        isRecordingShortcut.toggle()
    }

    func clearKeyShortcut() {
        keyShortcut = nil
        isRecordingShortcut = false
    }

    /// Processa uma tecla capturada no sheet. Retorna `true` se o evento foi consumido.
    @discardableResult
    func recordKey(keyCode: UInt16, modifiers: Set<MacroKeyModifier>) -> Bool {
        guard isRecordingShortcut else { return false }
        if keyCode == UInt16(kVK_Escape), modifiers.isEmpty {
            isRecordingShortcut = false
            return true
        }
        guard !MacroKeyFormatter.isModifierOnlyKey(keyCode) else { return true }
        keyShortcut = MacroKeyShortcut(keyCode: keyCode, modifiers: modifiers)
        isRecordingShortcut = false
        return true
    }

    // MARK: - Construção, teste e gravação

    func buildAction() -> MacroAction? {
        switch actionKind {
        case .keyboardShortcut:
            guard let keyShortcut else { return nil }
            return .keyboardShortcut(keyShortcut)
        case .shortcut:
            let trimmed = shortcutName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            return .shortcut(name: trimmed)
        case .open:
            return buildOpenAction()
        case .script:
            guard !scriptSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .script(kind: scriptKind, source: scriptSource)
        }
    }

    func buildMacro() -> Macro? {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, let action = buildAction() else { return nil }
        return Macro(
            id: editingMacroID ?? draftID,
            name: trimmedName,
            trigger: trigger,
            action: action
        )
    }

    func testMacro() async {
        guard let action = buildAction(), !isTesting else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = Macro(
            id: editingMacroID ?? draftID,
            name: trimmedName,
            trigger: trigger,
            action: action
        )
        isTesting = true
        testOutcome = nil
        let outcome = await runner.run(candidate)
        isTesting = false
        testOutcome = outcome
    }

    @discardableResult
    func save(
        isEarbudsConnected: Bool,
        applyGesture: (QCYKeyFunction, QCYGesture) -> Void
    ) throws -> MacroSaveOutcome? {
        guard let macro = buildMacro() else { return nil }
        saveError = nil

        let replaced = conflictingMacro
        do {
            if let replaced {
                try store.remove(id: replaced.id)
            }
            try store.upsert(macro)
        } catch let error as MacroStoreError {
            if let replaced, store.macro(for: replaced.trigger) == nil {
                try? store.upsert(replaced)
            }
            saveError = error
            throw error
        }

        if isEarbudsConnected {
            applyGesture(macro.trigger.keyFunction, targetGesture)
            return .savedAndApplied(macro)
        }
        return .savedOffline(macro)
    }
}

// MARK: - Helpers de construção e validação

extension MacroEditorModel {
    func load(action: MacroAction) {
        switch action {
        case .keyboardShortcut(let shortcut):
            actionKind = .keyboardShortcut
            keyShortcut = shortcut
        case .shortcut(let name):
            actionKind = .shortcut
            shortcutName = name
        case .open(let target):
            actionKind = .open
            switch target {
            case .appPath(let path):
                openKind = .app
                openValue = path
            case .bundleIdentifier(let bundleID):
                openKind = .app
                openValue = bundleID
            case .url(let targetURL):
                openKind = .url
                openValue = targetURL.absoluteString
            }
        case .script(let kind, let source):
            actionKind = .script
            scriptKind = kind
            scriptSource = source
        }
    }

    func buildOpenAction() -> MacroAction? {
        let trimmed = openValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        switch openKind {
        case .app:
            let lower = trimmed.lowercased()
            if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") || lower.hasSuffix(".app") {
                return .open(target: .appPath(trimmed))
            }
            return .open(target: .bundleIdentifier(trimmed))
        case .url:
            guard let targetURL = Self.validatedURL(from: trimmed) else { return nil }
            return .open(target: .url(targetURL))
        }
    }

    static func validatedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains(where: \.isWhitespace),
              let url = URL(string: trimmed),
              let scheme = url.scheme,
              !scheme.isEmpty,
              !trimmed.hasSuffix("://"),
              !trimmed.hasSuffix(":") else {
            return nil
        }
        let lowerScheme = scheme.lowercased()
        if lowerScheme == "http" || lowerScheme == "https" {
            guard let host = url.host, !host.isEmpty else { return nil }
        }
        return url
    }

    private static func existingMacro(
        for gesture: QCYGesture,
        keyMap: [QCYGesture: QCYKeyFunction],
        store: MacroStore
    ) -> Macro? {
        guard let function = keyMap[gesture],
              let command = MediaCommand(keyFunction: function) else {
            return nil
        }
        return store.macro(for: command)
    }

    private static func defaultTrigger(
        for gesture: QCYGesture,
        keyMap: [QCYGesture: QCYKeyFunction],
        store: MacroStore
    ) -> MediaCommand {
        if let currentFunction = keyMap[gesture],
           let currentCommand = MediaCommand(keyFunction: currentFunction),
           store.macro(for: currentCommand) == nil {
            return currentCommand
        }
        return MediaCommand.allCases.first { store.macro(for: $0) == nil } ?? .play
    }
}

// MARK: - Derivação de macro por gesto

extension QCYViewModel {
    /// Macro ativa para o gesto quando a função dele no fone é o gatilho de sacrifício de uma macro salva.
    func macro(for gesture: QCYGesture) -> Macro? {
        guard let function = keyMap[gesture],
              let trigger = MediaCommand(keyFunction: function) else {
            return nil
        }
        return macroStore.macro(for: trigger)
    }

    /// Outros gestos atualmente mapeados para a mesma função de sacrifício.
    func otherGestures(sharing trigger: MediaCommand, excluding gesture: QCYGesture) -> [QCYGesture] {
        QCYGesture.allOrdered.filter { candidate in
            candidate != gesture && keyMap[candidate] == trigger.keyFunction
        }
    }

    /// Apaga a macro do gatilho usado por `gesture` e devolve o gesto à função "nada" no fone.
    func removeMacro(for gesture: QCYGesture) throws {
        guard let macro = macro(for: gesture) else { return }
        try macroStore.remove(id: macro.id)
        if phase == .connected, !isReadOnly {
            choose(function: .unassigned, for: gesture)
        }
    }
}

extension QCYGesture {
    static var allOrdered: [QCYGesture] {
        Tap.allCases.flatMap { tap in
            [QCYGesture(side: .left, tap: tap), QCYGesture(side: .right, tap: tap)]
        }
    }
}
