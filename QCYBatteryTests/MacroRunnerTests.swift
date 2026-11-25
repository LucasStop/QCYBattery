import ApplicationServices
import Foundation
import os
import XCTest
@testable import QCYBattery

final class FakeMacroEffects: MacroEffects, Sendable {
    struct ProcessCall: Equatable, Sendable {
        let executableURL: URL
        let arguments: [String]
        let timeout: Duration
    }

    private struct State {
        var postedKeys: [MacroKeyShortcut] = []
        var shortcutNames: [String] = []
        var openedTargets: [MacroOpenTarget] = []
        var processCalls: [ProcessCall] = []
        var isAccessibilityTrusted = true
        var processDelay: Duration = .zero
        var forcedError: MacroExecutionError?
    }

    private let lock = OSAllocatedUnfairLock(initialState: State())

    var postedKeys: [MacroKeyShortcut] { lock.withLock { $0.postedKeys } }
    var shortcutNames: [String] { lock.withLock { $0.shortcutNames } }
    var openedTargets: [MacroOpenTarget] { lock.withLock { $0.openedTargets } }
    var processCalls: [ProcessCall] { lock.withLock { $0.processCalls } }

    func configure(
        isAccessibilityTrusted: Bool = true,
        processDelay: Duration = .zero,
        forcedError: MacroExecutionError? = nil
    ) {
        lock.withLock { state in
            state.isAccessibilityTrusted = isAccessibilityTrusted
            state.processDelay = processDelay
            state.forcedError = forcedError
        }
    }

    func postKey(_ shortcut: MacroKeyShortcut) async throws {
        let (trusted, forced) = lock.withLock { ($0.isAccessibilityTrusted, $0.forcedError) }
        if let forced { throw forced }
        guard trusted else { throw MacroExecutionError.accessibilityPermissionRequired }
        lock.withLock { $0.postedKeys.append(shortcut) }
    }

    func runShortcut(name: String, timeout: Duration) async throws {
        lock.withLock { $0.shortcutNames.append(name) }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MacroExecutionError.invalidTarget
        }
        _ = try await runProcess(
            executableURL: URL(fileURLWithPath: "/usr/bin/shortcuts"),
            arguments: ["run", name],
            timeout: timeout
        )
    }

    func open(_ target: MacroOpenTarget) async throws {
        if let forced = lock.withLock({ $0.forcedError }) { throw forced }
        lock.withLock { $0.openedTargets.append(target) }
    }

    func runProcess(
        executableURL: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> MacroProcessOutput {
        let call = ProcessCall(executableURL: executableURL, arguments: arguments, timeout: timeout)
        let (delay, forced) = lock.withLock { state -> (Duration, MacroExecutionError?) in
            state.processCalls.append(call)
            return (state.processDelay, state.forcedError)
        }
        if delay > .zero {
            try await Task.sleep(for: delay)
        }
        if let forced { throw forced }
        return MacroProcessOutput(exitCode: 0, wasTruncated: false)
    }
}

final class MacroRunnerTests: XCTestCase {
    func testKeyboardAndOpenActionsInvokeExpectedEffects() async throws {
        let effects = FakeMacroEffects()
        let logger = FakeMacroLogger()
        let runner = MacroRunner(effects: effects, logger: logger, timeout: .seconds(7))

        let keyMacro = Macro(
            name: "Tecla",
            trigger: .play,
            action: .keyboardShortcut(keyCode: 46, modifiers: [.command, .shift])
        )
        try await runner.execute(keyMacro)
        XCTAssertEqual(
            effects.postedKeys,
            [MacroKeyShortcut(keyCode: 46, modifiers: [.command, .shift])]
        )

        let targetURL = try XCTUnwrap(URL(string: "https://example.com"))
        let targets: [MacroOpenTarget] = [
            .appPath("/Applications/Safari.app"),
            .bundleIdentifier("com.apple.Safari"),
            .url(targetURL)
        ]
        for target in targets {
            try await runner.execute(Macro(name: "Abrir", trigger: .next, action: .open(target: target)))
        }
        XCTAssertEqual(effects.openedTargets, targets)
    }

    func testShellAndAppleScriptActionsInvokeExpectedInterpreters() async throws {
        let effects = FakeMacroEffects()
        let logger = FakeMacroLogger()
        let timeout: Duration = .seconds(7)
        let runner = MacroRunner(effects: effects, logger: logger, timeout: timeout)

        let shellMacro = Macro(
            name: "Shell",
            trigger: .previous,
            action: .script(kind: .shell, source: "echo test")
        )
        let appleMacro = Macro(
            name: "AppleScript",
            trigger: .previous,
            action: .script(kind: .appleScript, source: "beep")
        )
        try await runner.execute(shellMacro)
        try await runner.execute(appleMacro)

        XCTAssertEqual(
            effects.processCalls,
            [
                .init(
                    executableURL: URL(fileURLWithPath: "/bin/zsh"),
                    arguments: ["-c", "echo test"],
                    timeout: timeout
                ),
                .init(
                    executableURL: URL(fileURLWithPath: "/usr/bin/osascript"),
                    arguments: ["-e", "beep"],
                    timeout: timeout
                )
            ]
        )
    }

    func testShortcutNameWithSpacesAndQuotesPassesAsSingleArgumentWithoutShell() async throws {
        let effects = FakeMacroEffects()
        let logger = FakeMacroLogger()
        let runner = MacroRunner(effects: effects, logger: logger, timeout: .seconds(5))

        let trickyName = "Meu \"Atalho\" Com Espaços & Símbolos; $(whoami)"
        let macro = Macro(
            name: "Atalho",
            trigger: .play,
            action: .shortcut(name: trickyName)
        )

        let result = await runner.run(macro)
        XCTAssertEqual(result, .succeeded)
        XCTAssertEqual(effects.shortcutNames, [trickyName])
        XCTAssertEqual(effects.processCalls.count, 1)

        let call = try XCTUnwrap(effects.processCalls.first)
        XCTAssertEqual(call.executableURL.path, "/usr/bin/shortcuts")
        XCTAssertEqual(call.arguments.count, 2)
        XCTAssertEqual(call.arguments, ["run", trickyName])
    }

    func testScriptTimeoutCancelsExecutionAndReturnsTypedError() async {
        let effects = FakeMacroEffects()
        effects.configure(processDelay: .seconds(5))
        let logger = FakeMacroLogger()
        let runner = MacroRunner(effects: effects, logger: logger, timeout: .milliseconds(50))

        let macro = Macro(
            id: UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!,
            name: "Lento",
            trigger: .play,
            action: .script(kind: .shell, source: "sleep 60")
        )

        let result = await runner.run(macro)
        XCTAssertEqual(result, .failed(.timedOut))
        XCTAssertEqual(
            logger.errors,
            ["macro=AAAAAAAA-1111-2222-3333-BBBBBBBBBBBB result=error(timed_out)"]
        )
    }

    func testMissingAccessibilityReturnsTypedErrorAndPromptsOnlyOnFirstRun() async {
        let promptCalls = OSAllocatedUnfairLock(initialState: [Bool]())
        let posterCalled = OSAllocatedUnfairLock(initialState: false)

        let systemEffects = SystemMacroEffects(
            accessibilityChecker: { prompt in
                promptCalls.withLock { $0.append(prompt) }
                return false
            },
            keyEventPoster: { _ in
                posterCalled.withLock { $0 = true }
            }
        )

        // Inicializar o efeito e o runner nunca consulta nem pede Acessibilidade no lançamento.
        let logger = FakeMacroLogger()
        let runner = MacroRunner(effects: systemEffects, logger: logger)
        XCTAssertTrue(promptCalls.withLock { $0.isEmpty })

        let macro = Macro(
            name: "Mudo",
            trigger: .play,
            action: .keyboardShortcut(keyCode: 46, modifiers: [.command, .option, .control, .shift])
        )

        let firstResult = await runner.run(macro)
        let secondResult = await runner.run(macro)

        XCTAssertEqual(firstResult, .failed(.accessibilityPermissionRequired))
        XCTAssertEqual(secondResult, .failed(.accessibilityPermissionRequired))
        XCTAssertEqual(promptCalls.withLock { $0 }, [true, false])
        XCTAssertFalse(posterCalled.withLock { $0 })

        let flags = SystemMacroEffects.cgEventFlags(for: [.command, .shift, .option, .control])
        XCTAssertTrue(flags.contains(.maskCommand))
        XCTAssertTrue(flags.contains(.maskShift))
        XCTAssertTrue(flags.contains(.maskAlternate))
        XCTAssertTrue(flags.contains(.maskControl))
    }

    func testLogsAndErrorsNeverContainScriptSourceMacroNameOrArguments() async {
        let effects = FakeMacroEffects()
        let logger = FakeMacroLogger()
        let runner = MacroRunner(effects: effects, logger: logger, timeout: .milliseconds(50))

        let secretSource = "SUPER_SECRET_API_KEY=xyz_987654321; echo SECRET_OUTPUT"
        let secretName = "PRIVATE_MACRO_NAME_001"
        let macroID = UUID(uuidString: "cccccccc-dddd-eeee-ffff-000000000001")!
        let scriptMacro = Macro(
            id: macroID,
            name: secretName,
            trigger: .next,
            action: .script(kind: .shell, source: secretSource)
        )

        // Sucesso
        let okResult = await runner.run(scriptMacro)
        XCTAssertEqual(okResult, .succeeded)

        // Falha de processo
        effects.configure(forcedError: .processFailed(exitCode: 23))
        let failResult = await runner.run(scriptMacro)
        XCTAssertEqual(failResult, .failed(.processFailed(exitCode: 23)))

        // Script vazio
        let emptyMacro = Macro(
            name: secretName,
            trigger: .previous,
            action: .script(kind: .appleScript, source: "   \n ")
        )
        let emptyResult = await runner.run(emptyMacro)
        XCTAssertEqual(emptyResult, .failed(.emptyScript))

        for entry in logger.allMessages {
            XCTAssertFalse(entry.contains(secretSource), "Log leaked script source: \(entry)")
            XCTAssertFalse(entry.contains("SECRET_OUTPUT"), "Log leaked output token: \(entry)")
            XCTAssertFalse(entry.contains(secretName), "Log leaked macro name: \(entry)")
        }
        XCTAssertEqual(
            logger.infos,
            ["macro=\(macroID.uuidString) result=ok"]
        )
        XCTAssertTrue(
            logger.errors.contains("macro=\(macroID.uuidString) result=error(process_failed(23))")
        )

        let errorToCheck = MacroExecutionError.processFailed(exitCode: 23)
        XCTAssertFalse(String(describing: errorToCheck).contains(secretSource))
        XCTAssertFalse((errorToCheck.errorDescription ?? "").contains(secretSource))
    }
}
