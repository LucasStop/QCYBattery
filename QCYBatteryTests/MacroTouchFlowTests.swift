import Foundation
import QCYKit
import XCTest
@testable import QCYBattery

private final class MacroEditorFakeLink: QCYLink, @unchecked Sendable {
    struct KeyWrite: Equatable {
        let gesture: QCYGesture
        let function: QCYKeyFunction
    }

    var onState: (@Sendable (QCYState) -> Void)?
    var onAdvertisement: (@Sendable (QCYAdvertisement) -> Void)?
    var onReady: (@Sendable () -> Void)?
    var onDisconnect: (@Sendable () -> Void)?
    private(set) var keyWrites: [KeyWrite] = []

    func start() {}
    func stop() {}
    func refresh() {}
    func refreshKeyMap() {}
    func send(_ packet: QCYPacket) {}
    func setKeyFunction(_ function: QCYKeyFunction, for gesture: QCYGesture) {
        keyWrites.append(KeyWrite(gesture: gesture, function: function))
    }
}

@MainActor
final class MacroTouchFlowTests: XCTestCase {
    private static let baseKeyMap: [QCYGesture: QCYKeyFunction] = [
        .leftSingleTap: .unassigned,
        .rightSingleTap: .playPause,
        .leftDoubleTap: .previousTrack,
        .rightDoubleTap: .nextTrack,
        .leftTripleTap: .ancMode,
        .rightTripleTap: .voiceAssistant
    ]

    private func makeRunner(
        effects: FakeMacroEffects = FakeMacroEffects(),
        logger: FakeMacroLogger = FakeMacroLogger()
    ) -> MacroRunner {
        MacroRunner(effects: effects, logger: logger, timeout: .seconds(2))
    }

    private func connectedState(keyMap: [QCYGesture: QCYKeyFunction] = baseKeyMap) -> QCYState {
        var state = QCYState()
        state.left = QCYBatteryLevel(raw: 85)
        state.right = QCYBatteryLevel(raw: 88)
        state.keyMap = keyMap
        return state
    }

    private func flush() async {
        try? await Task.sleep(for: .milliseconds(30))
    }

    func testReplacingExistingTriggerWarnsAndReplacesMacro() throws {
        let existing = Macro(name: "Antiga", trigger: .play, action: .shortcut(name: "Velho"))
        let store = MacroStore.inMemory(macros: [existing])
        let editor = MacroEditorModel(
            targetGesture: .leftTripleTap,
            store: store,
            keyMap: Self.baseKeyMap,
            runner: makeRunner()
        )

        XCTAssertEqual(editor.trigger, .next)
        XCTAssertNil(editor.conflictingMacro)

        editor.trigger = .play
        XCTAssertEqual(editor.conflictingMacro, existing)

        editor.name = "Nova"
        editor.actionKind = .shortcut
        editor.shortcutName = "Novo"

        var appliedWrites: [(QCYKeyFunction, QCYGesture)] = []
        let outcome = try editor.save(isEarbudsConnected: true) { function, gesture in
            appliedWrites.append((function, gesture))
        }

        guard case .savedAndApplied(let saved)? = outcome else {
            return XCTFail("Expected savedAndApplied outcome")
        }
        XCTAssertEqual(saved.name, "Nova")
        XCTAssertEqual(saved.trigger, .play)
        XCTAssertEqual(store.macros.count, 1)
        XCTAssertEqual(store.macro(for: .play)?.name, "Nova")
        XCTAssertEqual(appliedWrites.count, 1)
        XCTAssertEqual(appliedWrites.first?.0, .playPause)
        XCTAssertEqual(appliedWrites.first?.1, .leftTripleTap)
    }

    func testEditingExistingMacroPreservesIDAndReassignsOverAnotherTrigger() throws {
        let macroPlay = Macro(
            name: "Mudo",
            trigger: .play,
            action: .keyboardShortcut(keyCode: 46, modifiers: [.command])
        )
        let macroNext = Macro(name: "Foco", trigger: .next, action: .shortcut(name: "Foco"))
        let store = MacroStore.inMemory(macros: [macroPlay, macroNext])
        let editor = MacroEditorModel(
            targetGesture: .rightSingleTap,
            store: store,
            keyMap: Self.baseKeyMap,
            runner: makeRunner()
        )

        XCTAssertEqual(editor.editingMacroID, macroPlay.id)
        XCTAssertEqual(editor.name, "Mudo")
        XCTAssertEqual(editor.trigger, .play)
        XCTAssertNil(editor.conflictingMacro)

        editor.trigger = .next
        XCTAssertEqual(editor.conflictingMacro, macroNext)

        _ = try editor.save(isEarbudsConnected: true) { _, _ in }
        XCTAssertEqual(store.macros.count, 1)
        XCTAssertNil(store.macro(for: .play))
        XCTAssertEqual(store.macro(for: .next)?.id, macroPlay.id)
        XCTAssertEqual(store.macro(for: .next)?.name, "Mudo")
    }

    func testSharedGesturesWarningAndOfflineSaveBehavior() throws {
        var keyMap = Self.baseKeyMap
        keyMap[.leftSingleTap] = .playPause
        keyMap[.rightSingleTap] = .playPause

        let store = MacroStore.inMemory()
        let editor = MacroEditorModel(
            targetGesture: .leftSingleTap,
            store: store,
            keyMap: keyMap,
            runner: makeRunner()
        )
        editor.trigger = .play
        XCTAssertEqual(editor.sharedGestures, [.rightSingleTap])

        editor.name = "Pausar"
        editor.actionKind = .shortcut
        editor.shortcutName = "Meu Atalho"

        var applied = false
        let outcome = try editor.save(isEarbudsConnected: false) { _, _ in
            applied = true
        }
        guard case .savedOffline(let saved)? = outcome else {
            return XCTFail("Expected savedOffline outcome")
        }
        XCTAssertFalse(applied)
        XCTAssertEqual(store.macro(for: .play), saved)
    }

    func testHasMacroDerivedFromKeyMapAndStoreAndRemoveMacro() async throws {
        let muteMacro = Macro(
            name: "Mudo",
            trigger: .play,
            action: .keyboardShortcut(keyCode: 46, modifiers: [.command, .shift])
        )
        let store = MacroStore.inMemory(macros: [muteMacro])
        let link = MacroEditorFakeLink()
        let model = QCYViewModel(link: link, macroStore: store)
        var keyMap = Self.baseKeyMap
        keyMap[.leftTripleTap] = .playPause
        link.onState?(connectedState(keyMap: keyMap))
        await flush()

        XCTAssertEqual(model.macro(for: .rightSingleTap), muteMacro)
        XCTAssertEqual(model.macro(for: .leftTripleTap), muteMacro)
        XCTAssertNil(model.macro(for: .rightDoubleTap))
        XCTAssertNil(model.macro(for: .leftSingleTap))
        XCTAssertEqual(model.otherGestures(sharing: .play, excluding: .leftTripleTap), [.rightSingleTap])

        try model.removeMacro(for: .leftTripleTap)
        XCTAssertTrue(store.macros.isEmpty)
        XCTAssertNil(model.macro(for: .leftTripleTap))
        XCTAssertNil(model.macro(for: .rightSingleTap))
        XCTAssertEqual(link.keyWrites, [.init(gesture: .leftTripleTap, function: .unassigned)])
        XCTAssertEqual(model.pending, .key(.leftTripleTap, .unassigned))
    }

    func testEarbudsWriteFailureKeepsSavedMacroInStore() async throws {
        let store = MacroStore.inMemory()
        let link = MacroEditorFakeLink()
        let model = QCYViewModel(link: link, writeTimeout: .milliseconds(40), macroStore: store)
        link.onState?(connectedState())
        await flush()

        let editor = MacroEditorModel(
            targetGesture: .leftTripleTap,
            store: store,
            keyMap: model.keyMap,
            runner: makeRunner()
        )
        editor.name = "Mudo"
        editor.trigger = .play
        editor.actionKind = .shortcut
        editor.shortcutName = "Mudo"

        _ = try editor.save(isEarbudsConnected: model.phase == .connected) { function, gesture in
            model.choose(function: function, for: gesture)
        }
        XCTAssertEqual(link.keyWrites, [.init(gesture: .leftTripleTap, function: .playPause)])

        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertTrue(model.writeFailed)
        XCTAssertEqual(model.keyMap[.leftTripleTap], .ancMode)
        XCTAssertEqual(store.macro(for: .play)?.name, "Mudo")
    }

    func testTestMacroUsesFakeEffectsAndNeverLeaksScriptContent() async {
        let effects = FakeMacroEffects()
        let logger = FakeMacroLogger()
        let editor = MacroEditorModel(
            targetGesture: .leftTripleTap,
            store: MacroStore.inMemory(),
            keyMap: Self.baseKeyMap,
            runner: makeRunner(effects: effects, logger: logger)
        )
        let secretScript = "SECRET_TOKEN_XYZ_999=1; echo LEAK_CHECK"
        editor.name = "Teste"
        editor.actionKind = .script
        editor.scriptKind = .shell
        editor.scriptSource = secretScript

        await editor.testMacro()
        XCTAssertEqual(editor.testOutcome, .succeeded)
        XCTAssertEqual(effects.processCalls.count, 1)
        XCTAssertEqual(effects.processCalls.first?.executableURL.path, "/bin/zsh")

        effects.configure(forcedError: .processFailed(exitCode: 42))
        await editor.testMacro()
        XCTAssertEqual(editor.testOutcome, .failed(.processFailed(exitCode: 42)))

        for entry in logger.allMessages {
            XCTAssertFalse(entry.contains(secretScript))
            XCTAssertFalse(entry.contains("LEAK_CHECK"))
        }
        if case .failed(let error) = editor.testOutcome {
            XCTAssertFalse((error.errorDescription ?? "").contains(secretScript))
        }
    }
}
