import Foundation
import os
import QCYKit
import XCTest
@testable import QCYBattery

final class FakeMacroLogger: MacroLogging, Sendable {
    private struct Entries {
        var infos: [String] = []
        var errors: [String] = []
    }

    private let lock = OSAllocatedUnfairLock(initialState: Entries())

    var infos: [String] { lock.withLock { $0.infos } }
    var errors: [String] { lock.withLock { $0.errors } }
    var allMessages: [String] { lock.withLock { $0.infos + $0.errors } }

    func info(_ message: String) {
        lock.withLock { $0.infos.append(message) }
    }

    func error(_ message: String) {
        lock.withLock { $0.errors.append(message) }
    }
}

@MainActor
final class MacroStoreTests: XCTestCase {
    private var tempDirectory: URL!
    private var fileURL: URL!
    private var logger: FakeMacroLogger!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QCYMacroStoreTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = tempDirectory.appendingPathComponent("QCYBattery/macros.json", isDirectory: false)
        logger = FakeMacroLogger()
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        fileURL = nil
        logger = nil
        try super.tearDownWithError()
    }

    func testMissingFileLoadsEmptyWithoutLoggingErrors() {
        let store = MacroStore(fileURL: fileURL, logger: logger)
        store.load()

        XCTAssertTrue(store.macros.isEmpty)
        XCTAssertTrue(store.activeTriggers.isEmpty)
        XCTAssertTrue(logger.allMessages.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fileURL.path))
    }

    func testRoundTripPersistsKeyboardShortcutAndBundleTargets() throws {
        let store = MacroStore(fileURL: fileURL, logger: logger)
        let firstBatch = [
            Macro(
                id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
                name: "Mudo",
                trigger: .play,
                action: .keyboardShortcut(keyCode: 46, modifiers: [.command, .shift])
            ),
            Macro(
                id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                name: "Foco",
                trigger: .next,
                action: .shortcut(name: "Modo Trabalho")
            ),
            Macro(
                id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
                name: "Música",
                trigger: .previous,
                action: .open(target: .bundleIdentifier("com.apple.Music"))
            )
        ]

        try store.save(firstBatch)

        let reloaded = MacroStore(fileURL: fileURL, logger: logger)
        reloaded.load()
        XCTAssertEqual(reloaded.macros, firstBatch)
        XCTAssertEqual(reloaded.activeTriggers, [.play, .next, .previous])
    }

    func testRoundTripPersistsAppPathURLAndScriptActions() throws {
        let store = MacroStore(fileURL: fileURL, logger: logger)
        let targetURL = try XCTUnwrap(URL(string: "https://example.com/status"))
        let secondBatch = [
            Macro(
                name: "Calculadora",
                trigger: .play,
                action: .open(target: .appPath("/System/Applications/Calculator.app"))
            ),
            Macro(
                name: "Painel",
                trigger: .next,
                action: .open(target: .url(targetURL))
            ),
            Macro(
                name: "Script Apple",
                trigger: .previous,
                action: .script(kind: .appleScript, source: "display notification \"Oi\"")
            )
        ]

        try store.save(secondBatch)
        let thirdReload = MacroStore(fileURL: fileURL, logger: logger)
        thirdReload.load()
        XCTAssertEqual(thirdReload.macros, secondBatch)

        let shellOnly = [
            Macro(
                name: "Shell",
                trigger: .play,
                action: .script(kind: .shell, source: "printf 'ok'")
            )
        ]
        try thirdReload.save(shellOnly)
        let fourthReload = MacroStore(fileURL: fileURL, logger: logger)
        fourthReload.load()
        XCTAssertEqual(fourthReload.macros, shellOnly)
    }

    func testCorruptedJSONIsIgnoredWithoutCrashingOrLoggingScriptSource() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let secretPayload = "SECRET_SCRIPT_PAYLOAD_DO_NOT_LEAK_42"
        let corrupted = Data("{\"version\":1,\"macros\":[{\"source\":\"\(secretPayload)\"".utf8)
        try corrupted.write(to: fileURL, options: .atomic)

        let store = MacroStore(fileURL: fileURL, logger: logger)
        store.load()

        XCTAssertTrue(store.macros.isEmpty)
        XCTAssertEqual(logger.errors.count, 1)
        for entry in logger.allMessages {
            XCTAssertFalse(entry.contains(secretPayload), "Leaked script payload in log: \(entry)")
        }
    }

    func testSaveAndUpsertRejectDuplicateTriggersPreservingPreviousState() throws {
        let store = MacroStore(fileURL: fileURL, logger: logger)
        let original = Macro(
            id: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            name: "Original",
            trigger: .play,
            action: .shortcut(name: "Atalho 1")
        )
        try store.save([original])

        let conflicting = Macro(
            id: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!,
            name: "Conflito",
            trigger: .play,
            action: .shortcut(name: "Atalho 2")
        )

        XCTAssertThrowsError(try store.upsert(conflicting)) { error in
            XCTAssertEqual(error as? MacroStoreError, .duplicateTrigger(.play))
        }
        XCTAssertEqual(store.macros, [original])

        let reloaded = MacroStore(fileURL: fileURL, logger: logger)
        reloaded.load()
        XCTAssertEqual(reloaded.macros, [original])

        var updatedSameID = original
        updatedSameID.name = "Atualizada"
        try store.upsert(updatedSameID)
        XCTAssertEqual(store.macros, [updatedSameID])

        try store.remove(id: original.id)
        XCTAssertTrue(store.macros.isEmpty)
    }

    func testDiskJSONWithDuplicateTriggerIsIgnoredWithoutLoggingScriptContent() throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let secretScript = "TOKEN_SECRET_987654"
        let duplicateJSON = """
        {
          "version": 1,
          "macros": [
            {
              "id": "11111111-1111-1111-1111-111111111111",
              "name": "Primeira",
              "trigger": "next",
              "action": { "type": "script", "kind": "shell", "source": "\(secretScript)" }
            },
            {
              "id": "22222222-2222-2222-2222-222222222222",
              "name": "Duplicada",
              "trigger": "next",
              "action": { "type": "shortcut", "name": "Outra" }
            }
          ]
        }
        """
        try Data(duplicateJSON.utf8).write(to: fileURL, options: .atomic)

        let store = MacroStore(fileURL: fileURL, logger: logger)
        store.load()

        XCTAssertTrue(store.macros.isEmpty)
        XCTAssertEqual(logger.errors.count, 1)
        for entry in logger.allMessages {
            XCTAssertFalse(entry.contains(secretScript))
        }
    }

    func testMediaCommandMapsToSacrificialEarbudFunction() {
        XCTAssertEqual(MediaCommand.play.keyFunction, .playPause)
        XCTAssertEqual(MediaCommand.next.keyFunction, .nextTrack)
        XCTAssertEqual(MediaCommand.previous.keyFunction, .previousTrack)
    }
}
