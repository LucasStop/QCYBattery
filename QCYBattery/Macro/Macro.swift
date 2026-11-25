import Foundation
import os
import QCYKit

/// Comando de mídia usado como gatilho de sacrifício no fone para disparar uma macro no Mac.
enum MediaCommand: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case play
    case next
    case previous

    /// Função correspondente gravada no fone (`QCYKeyFunction`) quando o gesto vira macro no Mac.
    var keyFunction: QCYKeyFunction {
        switch self {
        case .play: .playPause
        case .next: .nextTrack
        case .previous: .previousTrack
        }
    }

    init?(keyFunction: QCYKeyFunction) {
        switch keyFunction {
        case .playPause: self = .play
        case .nextTrack: self = .next
        case .previousTrack: self = .previous
        default: return nil
        }
    }
}

/// Modificadores aceitos em uma ação de atalho de teclado sintético (`CGEvent`).
enum MacroKeyModifier: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case command
    case shift
    case option
    case control
}

/// Combinação de código virtual de tecla (`CGKeyCode`) e modificadores para envio via `CGEvent`.
struct MacroKeyShortcut: Codable, Equatable, Hashable, Sendable {
    let keyCode: UInt16
    let modifiers: Set<MacroKeyModifier>

    init(keyCode: UInt16, modifiers: Set<MacroKeyModifier> = []) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let list = try container.decodeIfPresent([MacroKeyModifier].self, forKey: .modifiers) ?? []
        self.modifiers = Set(list)
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        let sorted = modifiers.sorted { $0.rawValue < $1.rawValue }
        try container.encode(sorted, forKey: .modifiers)
    }
}

/// Alvo de abertura para a ação `.open` via `NSWorkspace`.
enum MacroOpenTarget: Codable, Equatable, Hashable, Sendable {
    case appPath(String)
    case bundleIdentifier(String)
    case url(URL)

    private enum CodingKeys: String, CodingKey {
        case kind
        case value
    }

    private enum Kind: String, Codable {
        case appPath
        case bundleIdentifier
        case url
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .appPath:
            self = .appPath(try container.decode(String.self, forKey: .value))
        case .bundleIdentifier:
            self = .bundleIdentifier(try container.decode(String.self, forKey: .value))
        case .url:
            self = .url(try container.decode(URL.self, forKey: .value))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .appPath(let path):
            try container.encode(Kind.appPath, forKey: .kind)
            try container.encode(path, forKey: .value)
        case .bundleIdentifier(let identifier):
            try container.encode(Kind.bundleIdentifier, forKey: .kind)
            try container.encode(identifier, forKey: .value)
        case .url(let targetURL):
            try container.encode(Kind.url, forKey: .kind)
            try container.encode(targetURL, forKey: .value)
        }
    }
}

/// Interpretador usado para rodar scripts configurados pelo usuário.
enum MacroScriptKind: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case shell
    case appleScript
}

/// Ação executada no Mac quando o gatilho de mídia de uma macro é capturado.
enum MacroAction: Codable, Equatable, Sendable {
    case keyboardShortcut(MacroKeyShortcut)
    case shortcut(name: String)
    case open(target: MacroOpenTarget)
    case script(kind: MacroScriptKind, source: String)

    static func keyboardShortcut(
        keyCode: UInt16,
        modifiers: Set<MacroKeyModifier> = []
    ) -> MacroAction {
        .keyboardShortcut(MacroKeyShortcut(keyCode: keyCode, modifiers: modifiers))
    }

    private enum CodingKeys: String, CodingKey {
        case type
        case keyCode
        case modifiers
        case name
        case target
        case kind
        case source
    }

    private enum ActionType: String, Codable {
        case keyboardShortcut
        case shortcut
        case open
        case script
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let actionType = try container.decode(ActionType.self, forKey: .type)
        switch actionType {
        case .keyboardShortcut:
            let keyCode = try container.decode(UInt16.self, forKey: .keyCode)
            let modifiers = try container.decodeIfPresent([MacroKeyModifier].self, forKey: .modifiers) ?? []
            self = .keyboardShortcut(MacroKeyShortcut(keyCode: keyCode, modifiers: Set(modifiers)))
        case .shortcut:
            self = .shortcut(name: try container.decode(String.self, forKey: .name))
        case .open:
            self = .open(target: try container.decode(MacroOpenTarget.self, forKey: .target))
        case .script:
            let kind = try container.decode(MacroScriptKind.self, forKey: .kind)
            let source = try container.decode(String.self, forKey: .source)
            self = .script(kind: kind, source: source)
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .keyboardShortcut(let shortcut):
            try container.encode(ActionType.keyboardShortcut, forKey: .type)
            try container.encode(shortcut.keyCode, forKey: .keyCode)
            let sorted = shortcut.modifiers.sorted { $0.rawValue < $1.rawValue }
            try container.encode(sorted, forKey: .modifiers)
        case .shortcut(let name):
            try container.encode(ActionType.shortcut, forKey: .type)
            try container.encode(name, forKey: .name)
        case .open(let target):
            try container.encode(ActionType.open, forKey: .type)
            try container.encode(target, forKey: .target)
        case .script(let kind, let source):
            try container.encode(ActionType.script, forKey: .type)
            try container.encode(kind, forKey: .kind)
            try container.encode(source, forKey: .source)
        }
    }
}

/// Macro associada a um comando de mídia de sacrifício (no máximo uma por `MediaCommand`).
struct Macro: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var trigger: MediaCommand
    var action: MacroAction

    init(
        id: UUID = UUID(),
        name: String,
        trigger: MediaCommand,
        action: MacroAction
    ) {
        self.id = id
        self.name = name
        self.trigger = trigger
        self.action = action
    }
}

/// Canal de diagnóstico do módulo de macros. Recebe apenas identificadores e códigos de erro tipados,
/// nunca conteúdo de script, argumentos, saída, caminhos pessoais ou MAC.
protocol MacroLogging: Sendable {
    func info(_ message: String)
    func error(_ message: String)
}

struct OSMacroLogger: MacroLogging {
    private static let logger = Logger(subsystem: "com.lucasstop.QCYBattery", category: "Macro")

    func info(_ message: String) {
        Self.logger.info("\(message, privacy: .public)")
    }

    func error(_ message: String) {
        Self.logger.error("\(message, privacy: .public)")
    }
}
