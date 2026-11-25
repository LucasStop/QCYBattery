import AppKit
import ApplicationServices
import Darwin
import Foundation
import os

/// Resultado resumido de um processo filho (sem reter texto de saída).
struct MacroProcessOutput: Equatable, Sendable {
    let exitCode: Int32
    let wasTruncated: Bool

    init(exitCode: Int32 = 0, wasTruncated: Bool = false) {
        self.exitCode = exitCode
        self.wasTruncated = wasTruncated
    }
}

/// Efeitos colaterais no macOS abstraídos para os testes nunca postarem teclas, abrirem apps ou rodarem scripts reais.
protocol MacroEffects: Sendable {
    func postKey(_ shortcut: MacroKeyShortcut) async throws
    func runShortcut(name: String, timeout: Duration) async throws
    func open(_ target: MacroOpenTarget) async throws
    func runProcess(
        executableURL: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> MacroProcessOutput
}

extension MacroEffects {
    func runShortcut(name: String, timeout: Duration) async throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MacroExecutionError.invalidTarget
        }
        _ = try await runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
            arguments: ["run", name],
            timeout: timeout
        )
    }
}

/// Implementação real dos efeitos de macro fora do App Sandbox.
final class SystemMacroEffects: MacroEffects, Sendable {
    static let defaultMaxOutputBytes = 64 * 1024

    private let accessibilityChecker: @Sendable (_ prompt: Bool) -> Bool
    private let keyEventPoster: @Sendable (MacroKeyShortcut) throws -> Void
    private let maxOutputBytes: Int
    private let hasPromptedAccessibility = OSAllocatedUnfairLock(initialState: false)

    init(
        maxOutputBytes: Int = SystemMacroEffects.defaultMaxOutputBytes,
        accessibilityChecker: @escaping @Sendable (_ prompt: Bool) -> Bool =
            SystemMacroEffects.defaultAccessibilityCheck,
        keyEventPoster: @escaping @Sendable (MacroKeyShortcut) throws -> Void =
            SystemMacroEffects.defaultPostKeyEvent
    ) {
        self.maxOutputBytes = maxOutputBytes
        self.accessibilityChecker = accessibilityChecker
        self.keyEventPoster = keyEventPoster
    }

    func postKey(_ shortcut: MacroKeyShortcut) async throws {
        let shouldPrompt = hasPromptedAccessibility.withLock { prompted in
            if prompted { return false }
            prompted = true
            return true
        }
        guard accessibilityChecker(shouldPrompt) else {
            throw MacroExecutionError.accessibilityPermissionRequired
        }
        try keyEventPoster(shortcut)
    }

    func open(_ target: MacroOpenTarget) async throws {
        switch target {
        case .url(let targetURL):
            guard let scheme = targetURL.scheme, !scheme.isEmpty else {
                throw MacroExecutionError.invalidTarget
            }
            let opened = await MainActor.run { NSWorkspace.shared.open(targetURL) }
            guard opened else { throw MacroExecutionError.openFailed }
        case .appPath(let rawPath):
            let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw MacroExecutionError.invalidTarget }
            let expandedPath = (trimmed as NSString).expandingTildeInPath
            try await openApplication(at: URL(fileURLWithPath: expandedPath))
        case .bundleIdentifier(let rawIdentifier):
            let bundleID = rawIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty else { throw MacroExecutionError.invalidTarget }
            let resolvedURL = await MainActor.run {
                NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            }
            guard let appURL = resolvedURL else { throw MacroExecutionError.openFailed }
            try await openApplication(at: appURL)
        }
    }

    func runProcess(
        executableURL: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> MacroProcessOutput {
        try await BoundedProcessRunner.run(
            executableURL: executableURL,
            arguments: arguments,
            timeout: timeout,
            maxOutputBytes: maxOutputBytes
        )
    }

    private func openApplication(at appURL: URL) async throws {
        do {
            let configuration = NSWorkspace.OpenConfiguration()
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: configuration)
        } catch {
            throw MacroExecutionError.openFailed
        }
    }

    static func cgEventFlags(for modifiers: Set<MacroKeyModifier>) -> CGEventFlags {
        var flags: CGEventFlags = []
        if modifiers.contains(.command) { flags.insert(.maskCommand) }
        if modifiers.contains(.shift) { flags.insert(.maskShift) }
        if modifiers.contains(.option) { flags.insert(.maskAlternate) }
        if modifiers.contains(.control) { flags.insert(.maskControl) }
        return flags
    }

    nonisolated private static func defaultAccessibilityCheck(prompt: Bool) -> Bool {
        if prompt {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            return AXIsProcessTrustedWithOptions(options)
        }
        return AXIsProcessTrusted()
    }

    nonisolated private static func defaultPostKeyEvent(_ shortcut: MacroKeyShortcut) throws {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyCode = CGKeyCode(shortcut.keyCode)
        guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw MacroExecutionError.keyEventCreationFailed
        }
        let flags = cgEventFlags(for: shortcut.modifiers)
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }
}

/// Executor de `Process` com timeout, término forçado e dreno limitado de stdout/stderr.
private enum BoundedProcessRunner {
    private struct State {
        var capturedBytes = 0
        var wasTruncated = false
        var didTimeOut = false
        var continuation: CheckedContinuation<Int32, Never>?
        var exitCode: Int32?
    }

    private final class ProcessBox: @unchecked Sendable {
        let process = Process()
    }

    static func run(
        executableURL: URL,
        arguments: [String],
        timeout: Duration,
        maxOutputBytes: Int
    ) async throws -> MacroProcessOutput {
        let box = ProcessBox()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stateLock = OSAllocatedUnfairLock(initialState: State())

        configureProcess(box.process, executableURL: executableURL, arguments: arguments)
        box.process.standardOutput = stdoutPipe
        box.process.standardError = stderrPipe
        installBoundedDrain(on: stdoutPipe.fileHandleForReading, maxBytes: maxOutputBytes, stateLock: stateLock)
        installBoundedDrain(on: stderrPipe.fileHandleForReading, maxBytes: maxOutputBytes, stateLock: stateLock)
        installTerminationHandler(on: box.process, stdoutPipe: stdoutPipe, stderrPipe: stderrPipe, stateLock: stateLock)

        do {
            try box.process.run()
        } catch {
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            throw MacroExecutionError.launchFailed
        }

        let exitCode = await awaitTermination(box: box, timeout: timeout, stateLock: stateLock)
        let finalState = stateLock.withLock { $0 }
        if finalState.didTimeOut || Task.isCancelled {
            throw MacroExecutionError.timedOut
        }
        guard exitCode == 0 else {
            throw MacroExecutionError.processFailed(exitCode: exitCode)
        }
        return MacroProcessOutput(exitCode: 0, wasTruncated: finalState.wasTruncated)
    }

    private static func installTerminationHandler(
        on process: Process,
        stdoutPipe: Pipe,
        stderrPipe: Pipe,
        stateLock: OSAllocatedUnfairLock<State>
    ) {
        process.terminationHandler = { finished in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil
            let status = finished.terminationReason == .uncaughtSignal
                ? -finished.terminationStatus
                : finished.terminationStatus
            let pending = stateLock.withLock { state -> CheckedContinuation<Int32, Never>? in
                state.exitCode = status
                let continuation = state.continuation
                state.continuation = nil
                return continuation
            }
            pending?.resume(returning: status)
        }
    }

    private static func awaitTermination(
        box: ProcessBox,
        timeout: Duration,
        stateLock: OSAllocatedUnfairLock<State>
    ) async -> Int32 {
        let terminateChild: @Sendable () -> Void = { terminate(box) }
        let timeoutTask = Task {
            try await Task.sleep(for: timeout)
            stateLock.withLock { $0.didTimeOut = true }
            terminateChild()
        }
        let exitCode = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Int32, Never>) in
                let finishedCode = stateLock.withLock { state -> Int32? in
                    if let code = state.exitCode { return code }
                    state.continuation = continuation
                    return nil
                }
                if let finishedCode {
                    continuation.resume(returning: finishedCode)
                }
            }
        } onCancel: {
            stateLock.withLock { $0.didTimeOut = true }
            terminateChild()
        }
        timeoutTask.cancel()
        return exitCode
    }

    private static func configureProcess(_ process: Process, executableURL: URL, arguments: [String]) {
        process.executableURL = executableURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
    }

    private static func installBoundedDrain(
        on handle: FileHandle,
        maxBytes: Int,
        stateLock: OSAllocatedUnfairLock<State>
    ) {
        handle.readabilityHandler = { readable in
            let chunk = readable.availableData
            guard !chunk.isEmpty else {
                readable.readabilityHandler = nil
                return
            }
            stateLock.withLock { state in
                let remaining = max(0, maxBytes - state.capturedBytes)
                state.capturedBytes += min(chunk.count, remaining)
                if chunk.count > remaining {
                    state.wasTruncated = true
                }
            }
        }
    }

    private static func terminate(_ box: ProcessBox) {
        guard box.process.isRunning else { return }
        box.process.terminate()
        let pid = box.process.processIdentifier
        guard pid > 0 else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + .milliseconds(200)) {
            if box.process.isRunning {
                _ = kill(pid, SIGKILL)
            }
        }
    }
}
