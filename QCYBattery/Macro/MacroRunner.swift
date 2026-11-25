import Foundation

/// Erros tipados na execução de macros. Nenhum caso armazena código de script, argumentos ou saída.
enum MacroExecutionError: Error, LocalizedError, CustomLocalizedStringResourceConvertible, Equatable, Sendable {
    case accessibilityPermissionRequired
    case keyEventCreationFailed
    case invalidTarget
    case openFailed
    case emptyScript
    case launchFailed
    case timedOut
    case processFailed(exitCode: Int32)

    var logCode: String {
        switch self {
        case .accessibilityPermissionRequired: "accessibility_permission_required"
        case .keyEventCreationFailed: "key_event_creation_failed"
        case .invalidTarget: "invalid_target"
        case .openFailed: "open_failed"
        case .emptyScript: "empty_script"
        case .launchFailed: "launch_failed"
        case .timedOut: "timed_out"
        case .processFailed(let exitCode): "process_failed(\(exitCode))"
        }
    }

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .accessibilityPermissionRequired: "qcy.macro.error.accessibilityRequired"
        case .keyEventCreationFailed: "qcy.macro.error.keyEventFailed"
        case .invalidTarget: "qcy.macro.error.invalidTarget"
        case .openFailed: "qcy.macro.error.openFailed"
        case .emptyScript: "qcy.macro.error.emptyScript"
        case .launchFailed: "qcy.macro.error.launchFailed"
        case .timedOut: "qcy.macro.error.timedOut"
        case .processFailed: "qcy.macro.error.processFailed"
        }
    }

    var errorDescription: String? {
        String(localized: localizedStringResource)
    }
}

/// Desfecho tipado e `Equatable` da execução de uma macro.
enum MacroRunOutcome: Equatable, Sendable {
    case succeeded
    case failed(MacroExecutionError)
}

/// Motor de execução de `Macro` atrás de `MacroEffects`, com timeout e log sanitizado.
struct MacroRunner: Sendable {
    static let defaultTimeout: Duration = .seconds(10)

    let effects: any MacroEffects
    let logger: any MacroLogging
    let timeout: Duration

    init(
        effects: any MacroEffects = SystemMacroEffects(),
        logger: any MacroLogging = OSMacroLogger(),
        timeout: Duration = MacroRunner.defaultTimeout
    ) {
        self.effects = effects
        self.logger = logger
        self.timeout = timeout
    }

    @discardableResult
    func run(_ macro: Macro) async -> MacroRunOutcome {
        do {
            try await execute(macro)
            return .succeeded
        } catch let error as MacroExecutionError {
            return .failed(error)
        } catch {
            return .failed(.launchFailed)
        }
    }

    func execute(_ macro: Macro) async throws {
        do {
            try await performAction(macro.action)
            logger.info("macro=\(macro.id.uuidString) result=ok")
        } catch let error as MacroExecutionError {
            logger.error("macro=\(macro.id.uuidString) result=error(\(error.logCode))")
            throw error
        } catch is CancellationError {
            let error = MacroExecutionError.timedOut
            logger.error("macro=\(macro.id.uuidString) result=error(\(error.logCode))")
            throw error
        } catch {
            let mapped = MacroExecutionError.launchFailed
            logger.error("macro=\(macro.id.uuidString) result=error(\(mapped.logCode))")
            throw mapped
        }
    }

    private func performAction(_ action: MacroAction) async throws {
        switch action {
        case .keyboardShortcut(let shortcut):
            try await effects.postKey(shortcut)
        case .shortcut(let name):
            try await runWithTimeout {
                try await effects.runShortcut(name: name, timeout: timeout)
            }
        case .open(let target):
            try await effects.open(target)
        case .script(let kind, let source):
            guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw MacroExecutionError.emptyScript
            }
            let invocation = Self.scriptInvocation(kind: kind, source: source)
            try await runWithTimeout {
                _ = try await effects.runProcess(
                    executableURL: invocation.executableURL,
                    arguments: invocation.arguments,
                    timeout: timeout
                )
            }
        }
    }

    static func scriptInvocation(
        kind: MacroScriptKind,
        source: String
    ) -> (executableURL: URL, arguments: [String]) {
        switch kind {
        case .shell:
            (URL(fileURLWithPath: "/bin/zsh"), ["-c", source])
        case .appleScript:
            (URL(fileURLWithPath: "/usr/bin/osascript"), ["-e", source])
        }
    }

    private func runWithTimeout(_ operation: @escaping @Sendable () async throws -> Void) async throws {
        let limit = timeout
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                try await Task.sleep(for: limit)
                throw MacroExecutionError.timedOut
            }
            do {
                _ = try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                throw error
            }
        }
    }
}
