import Foundation
import XCTest
@testable import QCYBattery

@MainActor
private final class FakeGestureSource: GestureSource {
    var onCommand: ((MediaCommand) -> Bool)?
    private(set) var activeCommandsHistory: [Set<MediaCommand>] = []
    private(set) var currentActiveCommands: Set<MediaCommand> = []
    private(set) var stopCount = 0

    func updateActiveCommands(_ commands: Set<MediaCommand>) {
        currentActiveCommands = commands
        activeCommandsHistory.append(commands)
    }

    func stop() {
        currentActiveCommands = []
        stopCount += 1
    }

    func simulate(_ command: MediaCommand) -> Bool {
        onCommand?(command) ?? false
    }
}

@MainActor
final class MacroCoordinatorTests: XCTestCase {
    private var tempDirectory: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QCYMacroCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        fileURL = tempDirectory.appendingPathComponent("QCYBattery/macros.json", isDirectory: false)
    }

    override func tearDownWithError() throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        fileURL = nil
        try super.tearDownWithError()
    }

    private struct Fixture {
        let store: MacroStore
        let effects: FakeMacroEffects
        let source: FakeGestureSource
        let logger: FakeMacroLogger
        let coordinator: MacroCoordinator
    }

    private func makeFixture() -> Fixture {
        let logger = FakeMacroLogger()
        let store = MacroStore(fileURL: fileURL, logger: logger)
        let effects = FakeMacroEffects()
        let runner = MacroRunner(effects: effects, logger: logger, timeout: .seconds(1))
        let source = FakeGestureSource()
        let coordinator = MacroCoordinator(store: store, runner: runner, gestureSource: source)
        return Fixture(
            store: store,
            effects: effects,
            source: source,
            logger: logger,
            coordinator: coordinator
        )
    }

    func testStartWithNoMacrosRemainsInertWithoutCheckingAccessibility() {
        let fixture = makeFixture()
        var checkedAccessibility = false
        let tapSource = MediaKeyEventTapGestureSource {
            checkedAccessibility = true
            return false
        }
        tapSource.updateActiveCommands([])
        XCTAssertFalse(checkedAccessibility)

        fixture.coordinator.start()

        XCTAssertTrue(fixture.store.macros.isEmpty)
        XCTAssertEqual(fixture.source.activeCommandsHistory, [[]])
        XCTAssertFalse(fixture.source.simulate(.play))
        XCTAssertTrue(fixture.effects.postedKeys.isEmpty)
        XCTAssertTrue(fixture.effects.processCalls.isEmpty)
    }

    func testCommandWithRegisteredMacroCapturesEventAndRunsAction() async throws {
        let fixture = makeFixture()
        let macro = Macro(
            name: "Próxima vira Mudo",
            trigger: .next,
            action: .keyboardShortcut(keyCode: 46, modifiers: [.command, .shift])
        )
        try fixture.store.save([macro])

        let completed = expectation(description: "Macro execution completed")
        var recordedID: UUID?
        var recordedResult: MacroRunOutcome?
        fixture.coordinator.onExecutionCompleted = { id, result in
            recordedID = id
            recordedResult = result
            completed.fulfill()
        }

        fixture.coordinator.start()
        XCTAssertEqual(fixture.source.currentActiveCommands, [.next])

        let wasCaptured = fixture.source.simulate(.next)
        XCTAssertTrue(wasCaptured)

        await fulfillment(of: [completed], timeout: 1.0)
        XCTAssertEqual(recordedID, macro.id)
        XCTAssertEqual(recordedResult, .succeeded)
        XCTAssertEqual(
            fixture.effects.postedKeys,
            [MacroKeyShortcut(keyCode: 46, modifiers: [.command, .shift])]
        )
    }

    func testCommandWithoutMatchingMacroDoesNotCaptureAndLeavesMediaAlone() throws {
        let fixture = makeFixture()
        let macro = Macro(
            name: "Apenas Próxima",
            trigger: .next,
            action: .shortcut(name: "Foco")
        )
        try fixture.store.save([macro])
        fixture.coordinator.start()

        XCTAssertFalse(fixture.source.simulate(.play))
        XCTAssertFalse(fixture.source.simulate(.previous))
        XCTAssertTrue(fixture.effects.shortcutNames.isEmpty)
        XCTAssertTrue(fixture.effects.processCalls.isEmpty)
    }

    func testMutatingStoreUpdatesActiveCommandsAndStopReleasesGestureSource() throws {
        let fixture = makeFixture()
        fixture.coordinator.start()
        XCTAssertEqual(fixture.source.currentActiveCommands, [])

        let playMacro = Macro(name: "Play", trigger: .play, action: .shortcut(name: "Um"))
        let prevMacro = Macro(name: "Prev", trigger: .previous, action: .shortcut(name: "Dois"))
        try fixture.store.upsert(playMacro)
        XCTAssertEqual(fixture.source.currentActiveCommands, [.play])

        try fixture.store.upsert(prevMacro)
        XCTAssertEqual(fixture.source.currentActiveCommands, [.play, .previous])

        try fixture.store.remove(id: playMacro.id)
        XCTAssertEqual(fixture.source.currentActiveCommands, [.previous])

        fixture.coordinator.stop()
        XCTAssertEqual(fixture.source.stopCount, 1)
        XCTAssertFalse(fixture.coordinator.handle(.previous))
    }

    func testMediaKeyEventParserDecodesMediaKeysAndIgnoresOtherSystemEvents() {
        func makeData1(keyCode: Int, keyState: Int, isRepeat: Bool = false) -> Int {
            (keyCode << 16) | (keyState << 8) | (isRepeat ? 1 : 0)
        }

        XCTAssertEqual(
            MediaKeyEventParser.parse(subtype: 8, data1: makeData1(keyCode: 16, keyState: 0x0A)),
            ParsedMediaKeyEvent(command: .play, isKeyDown: true, isRepeat: false)
        )
        XCTAssertEqual(
            MediaKeyEventParser.parse(subtype: 8, data1: makeData1(keyCode: 17, keyState: 0x0B)),
            ParsedMediaKeyEvent(command: .next, isKeyDown: false, isRepeat: false)
        )
        XCTAssertEqual(
            MediaKeyEventParser.parse(subtype: 8, data1: makeData1(keyCode: 19, keyState: 0x0A, isRepeat: true)),
            ParsedMediaKeyEvent(command: .next, isKeyDown: true, isRepeat: true)
        )
        XCTAssertEqual(
            MediaKeyEventParser.parse(subtype: 8, data1: makeData1(keyCode: 18, keyState: 0x0A)),
            ParsedMediaKeyEvent(command: .previous, isKeyDown: true, isRepeat: false)
        )
        XCTAssertEqual(
            MediaKeyEventParser.parse(subtype: 8, data1: makeData1(keyCode: 20, keyState: 0x0B)),
            ParsedMediaKeyEvent(command: .previous, isKeyDown: false, isRepeat: false)
        )

        // Volume Up (keyCode 0) e subtipos fora de AUX_CONTROL_BUTTONS não são capturados.
        XCTAssertNil(MediaKeyEventParser.parse(subtype: 8, data1: makeData1(keyCode: 0, keyState: 0x0A)))
        XCTAssertNil(MediaKeyEventParser.parse(subtype: 4, data1: makeData1(keyCode: 16, keyState: 0x0A)))
    }
}
