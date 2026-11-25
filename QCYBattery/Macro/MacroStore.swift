import Foundation
import Observation

/// Erros de validação e gravação do `MacroStore` (sem conteúdo sensível do usuário).
enum MacroStoreError: Error, LocalizedError, CustomLocalizedStringResourceConvertible, Equatable, Sendable {
    case duplicateTrigger(MediaCommand)
    case persistenceFailed

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .duplicateTrigger: "qcy.macro.error.duplicateTrigger"
        case .persistenceFailed: "qcy.macro.error.persistenceFailed"
        }
    }

    var errorDescription: String? {
        String(localized: localizedStringResource)
    }
}

private struct MacroStoreDocument: Codable {
    static let currentVersion = 1

    let version: Int
    let macros: [Macro]
}

/// Persistência atômica das macros em `Application Support/QCYBattery/macros.json`.
/// Garante no máximo uma macro por `MediaCommand` e ignora JSON corrompido sem derrubar o app
/// nem registrar conteúdo de scripts em log.
@MainActor
@Observable
final class MacroStore {
    private(set) var macros: [Macro] = []

    @ObservationIgnored var onChange: (([Macro]) -> Void)?
    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private let fileManager: FileManager
    @ObservationIgnored private let logger: any MacroLogging

    init(
        fileURL: URL = MacroStore.defaultFileURL(),
        fileManager: FileManager = .default,
        logger: any MacroLogging = OSMacroLogger()
    ) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.logger = logger
    }

    static func defaultFileURL(fileManager: FileManager = .default) -> URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL
            .appendingPathComponent("QCYBattery", isDirectory: true)
            .appendingPathComponent("macros.json", isDirectory: false)
    }

    var activeTriggers: Set<MediaCommand> {
        Set(macros.map(\.trigger))
    }

    func macro(for trigger: MediaCommand) -> Macro? {
        macros.first { $0.trigger == trigger }
    }

    /// Carrega `macros.json` do disco. Arquivo ausente mantém a lista vazia em silêncio;
    /// arquivo ilegível, corrompido ou com gatilho duplicado é ignorado com log estático sem payload.
    func load() {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            applyLoaded([])
            return
        }

        let rawData: Data
        do {
            rawData = try Data(contentsOf: fileURL)
        } catch {
            logger.error("macros.json load failed: unreadable_file")
            applyLoaded([])
            return
        }

        let document: MacroStoreDocument
        do {
            document = try JSONDecoder().decode(MacroStoreDocument.self, from: rawData)
        } catch {
            logger.error("macros.json load failed: invalid_json")
            applyLoaded([])
            return
        }

        guard document.version == MacroStoreDocument.currentVersion else {
            logger.error("macros.json load failed: unsupported_version(\(document.version))")
            applyLoaded([])
            return
        }

        do {
            try Self.validateUniqueTriggers(document.macros)
        } catch {
            logger.error("macros.json load failed: duplicate_trigger")
            applyLoaded([])
            return
        }

        applyLoaded(document.macros)
    }

    /// Valida unicidade por gatilho e grava atomicamente em `macros.json`.
    func save(_ updated: [Macro]) throws {
        try Self.validateUniqueTriggers(updated)

        let directoryURL = fileURL.deletingLastPathComponent()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = MacroStoreDocument(
            version: MacroStoreDocument.currentVersion,
            macros: updated
        )

        do {
            try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            let encoded = try encoder.encode(document)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("macros.json save failed: io_error")
            throw MacroStoreError.persistenceFailed
        }

        macros = updated
        onChange?(macros)
    }

    /// Insere ou substitui a macro com o mesmo `id`, preservando a regra de um gatilho por `MediaCommand`.
    func upsert(_ macro: Macro) throws {
        var updated = macros
        if let existingIndex = updated.firstIndex(where: { $0.id == macro.id }) {
            updated[existingIndex] = macro
        } else {
            updated.append(macro)
        }
        try save(updated)
    }

    func remove(id: UUID) throws {
        let updated = macros.filter { $0.id != id }
        try save(updated)
    }

    static func validateUniqueTriggers(_ candidates: [Macro]) throws {
        var seen: Set<MediaCommand> = []
        for candidate in candidates where !seen.insert(candidate.trigger).inserted {
            throw MacroStoreError.duplicateTrigger(candidate.trigger)
        }
    }

    private func applyLoaded(_ loaded: [Macro]) {
        macros = loaded
        onChange?(macros)
    }
}
