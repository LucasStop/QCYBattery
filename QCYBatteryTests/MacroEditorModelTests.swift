import Carbon.HIToolbox
import Foundation
import QCYKit
import XCTest
@testable import QCYBattery

@MainActor
final class MacroEditorModelTests: XCTestCase {
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

    func testValidationForNameAndKeyboardShortcut() {
        let editor = MacroEditorModel(
            targetGesture: .leftTripleTap,
            store: MacroStore.inMemory(),
            keyMap: Self.baseKeyMap,
            runner: makeRunner()
        )

        XCTAssertFalse(editor.isNameValid)
        XCTAssertFalse(editor.isActionValid)
        XCTAssertFalse(editor.canSave)
        XCTAssertFalse(editor.canTest)

        editor.name = "Mudo"
        XCTAssertFalse(editor.canSave)

        editor.toggleShortcutRecording()
        XCTAssertTrue(editor.isRecordingShortcut)
        XCTAssertTrue(editor.recordKey(keyCode: 55, modifiers: [.command]))
        XCTAssertNil(editor.keyShortcut)
        XCTAssertTrue(editor.isRecordingShortcut)

        XCTAssertTrue(editor.recordKey(keyCode: UInt16(kVK_Escape), modifiers: []))
        XCTAssertFalse(editor.isRecordingShortcut)
        XCTAssertNil(editor.keyShortcut)

        editor.toggleShortcutRecording()
        XCTAssertTrue(editor.recordKey(keyCode: UInt16(kVK_ANSI_M), modifiers: [.command, .shift]))
        XCTAssertFalse(editor.isRecordingShortcut)
        XCTAssertTrue(editor.canSave)
        XCTAssertTrue(editor.canTest)

        editor.name = "   \n "
        XCTAssertFalse(editor.canSave)
        XCTAssertTrue(editor.canTest)

        editor.name = "Mudo"
        editor.clearKeyShortcut()
        XCTAssertFalse(editor.canSave)
    }

    func testValidationForShortcutOpenAndScriptActions() {
        let editor = MacroEditorModel(
            targetGesture: .leftTripleTap,
            store: MacroStore.inMemory(),
            keyMap: Self.baseKeyMap,
            runner: makeRunner()
        )
        editor.name = "Ação"

        editor.actionKind = .shortcut
        editor.shortcutName = "   "
        XCTAssertFalse(editor.canSave)
        editor.shortcutName = "Modo Trabalho"
        XCTAssertTrue(editor.canSave)

        editor.actionKind = .open
        editor.openKind = .app
        editor.openValue = ""
        XCTAssertFalse(editor.canSave)
        editor.openValue = "com.apple.Music"
        XCTAssertTrue(editor.canSave)

        editor.openKind = .url
        editor.openValue = "example.com"
        XCTAssertTrue(editor.isURLMissingScheme)
        XCTAssertFalse(editor.canSave)
        editor.openValue = "https://"
        XCTAssertTrue(editor.isURLMissingScheme)
        XCTAssertFalse(editor.canSave)
        editor.openValue = "https://example.com/status"
        XCTAssertFalse(editor.isURLMissingScheme)
        XCTAssertTrue(editor.canSave)
        editor.openValue = "obsidian://open?vault=Notas"
        XCTAssertFalse(editor.isURLMissingScheme)
        XCTAssertTrue(editor.canSave)

        editor.actionKind = .script
        editor.scriptSource = "  \n "
        XCTAssertFalse(editor.canSave)
        editor.scriptSource = "echo ok"
        XCTAssertTrue(editor.canSave)
    }

    func testBuildMacroForKeyboardAndShortcutsAppActions() throws {
        let editor = MacroEditorModel(
            targetGesture: .leftTripleTap,
            store: MacroStore.inMemory(),
            keyMap: Self.baseKeyMap,
            runner: makeRunner()
        )
        editor.name = "  Minha Macro  "
        editor.trigger = .next

        editor.actionKind = .keyboardShortcut
        editor.keyShortcut = MacroKeyShortcut(keyCode: 46, modifiers: [.command, .shift])
        let keyMacro = try XCTUnwrap(editor.buildMacro())
        XCTAssertEqual(keyMacro.name, "Minha Macro")
        XCTAssertEqual(keyMacro.trigger, .next)
        XCTAssertEqual(keyMacro.action, .keyboardShortcut(keyCode: 46, modifiers: [.command, .shift]))

        editor.actionKind = .shortcut
        editor.shortcutName = "  Modo Foco  "
        let shortcutMacro = try XCTUnwrap(editor.buildMacro())
        XCTAssertEqual(shortcutMacro.action, .shortcut(name: "Modo Foco"))
    }

    func testBuildMacroForOpenAndScriptActions() throws {
        let editor = MacroEditorModel(
            targetGesture: .leftTripleTap,
            store: MacroStore.inMemory(),
            keyMap: Self.baseKeyMap,
            runner: makeRunner()
        )
        editor.name = "Abrir"
        editor.trigger = .previous

        editor.actionKind = .open
        editor.openKind = .app
        editor.openValue = "/System/Applications/Calculator.app"
        XCTAssertEqual(
            try XCTUnwrap(editor.buildMacro()).action,
            .open(target: .appPath("/System/Applications/Calculator.app"))
        )

        editor.openValue = "com.apple.Music"
        XCTAssertEqual(
            try XCTUnwrap(editor.buildMacro()).action,
            .open(target: .bundleIdentifier("com.apple.Music"))
        )

        editor.openKind = .url
        editor.openValue = "https://example.com"
        XCTAssertEqual(
            try XCTUnwrap(editor.buildMacro()).action,
            .open(target: .url(try XCTUnwrap(URL(string: "https://example.com"))))
        )

        editor.actionKind = .script
        editor.scriptKind = .shell
        editor.scriptSource = "printf 'ok'"
        XCTAssertEqual(
            try XCTUnwrap(editor.buildMacro()).action,
            .script(kind: .shell, source: "printf 'ok'")
        )

        editor.scriptKind = .appleScript
        editor.scriptSource = "beep"
        XCTAssertEqual(
            try XCTUnwrap(editor.buildMacro()).action,
            .script(kind: .appleScript, source: "beep")
        )
    }

    func testKeyFormatterUsesCanonicalMacOSModifierOrder() {
        let full = MacroKeyShortcut(
            keyCode: UInt16(kVK_ANSI_M),
            modifiers: [.command, .shift, .option, .control]
        )
        XCTAssertEqual(MacroKeyFormatter.format(full), "⌃ ⌥ ⇧ ⌘ M")

        let space = MacroKeyShortcut(keyCode: UInt16(kVK_Space), modifiers: [.command])
        XCTAssertEqual(MacroKeyFormatter.format(space), "⌘ Space")

        let unknown = MacroKeyShortcut(keyCode: 200, modifiers: [])
        XCTAssertEqual(MacroKeyFormatter.format(unknown), "Key 200")
    }
}
