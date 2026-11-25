import QCYKit
import XCTest
@testable import QCYBattery

private final class TouchFakeLink: QCYLink, @unchecked Sendable {
    struct KeyWrite: Equatable {
        let gesture: QCYGesture
        let function: QCYKeyFunction
    }

    var onState: (@Sendable (QCYState) -> Void)?
    var onAdvertisement: (@Sendable (QCYAdvertisement) -> Void)?
    var onReady: (@Sendable () -> Void)?
    var onDisconnect: (@Sendable () -> Void)?
    private(set) var keyWrites: [KeyWrite] = []
    private(set) var refreshKeyMapCount = 0

    func start() {}
    func stop() {}
    func refresh() {}
    func refreshKeyMap() { refreshKeyMapCount += 1 }
    func send(_ packet: QCYPacket) {}
    func setKeyFunction(_ function: QCYKeyFunction, for gesture: QCYGesture) {
        keyWrites.append(KeyWrite(gesture: gesture, function: function))
    }
}

@MainActor
final class QCYTouchViewModelTests: XCTestCase {
    private static let defaultKeyMap: [QCYGesture: QCYKeyFunction] = [
        .leftSingleTap: .unassigned,
        .rightSingleTap: .playPause,
        .leftDoubleTap: .previousTrack,
        .rightDoubleTap: .nextTrack,
        .leftTripleTap: .ancMode,
        .rightTripleTap: .voiceAssistant
    ]

    private func makeModel(
        readOnly: Bool = false,
        writeTimeout: Duration = .seconds(5),
        pollInterval: Duration = .seconds(30)
    ) -> (QCYViewModel, TouchFakeLink) {
        let link = TouchFakeLink()
        let model = QCYViewModel(
            link: link,
            isReadOnly: readOnly,
            writeTimeout: writeTimeout,
            pollInterval: pollInterval
        )
        return (model, link)
    }

    private func state(keyMap: [QCYGesture: QCYKeyFunction] = defaultKeyMap) -> QCYState {
        var state = QCYState()
        state.left = QCYBatteryLevel(raw: 90)
        state.right = QCYBatteryLevel(raw: 91)
        state.keyMap = keyMap
        return state
    }

    private func flush() async { try? await Task.sleep(for: .milliseconds(30)) }

    func testChoosingKeyFunctionSendsWriteAndConfirmsOnEcho() async {
        let (model, link) = makeModel()
        link.onState?(state())
        await flush()

        model.choose(function: .volumeUp, for: .leftSingleTap)
        XCTAssertEqual(link.keyWrites, [.init(gesture: .leftSingleTap, function: .volumeUp)])
        XCTAssertEqual(model.pending, .key(.leftSingleTap, .volumeUp))
        XCTAssertEqual(model.keyMap[.leftSingleTap], .volumeUp)
        XCTAssertTrue(model.areControlsDisabled)

        // Estado antigo sem o eco não confirma.
        link.onState?(state())
        await flush()
        XCTAssertEqual(model.pending, .key(.leftSingleTap, .volumeUp))

        var updated = Self.defaultKeyMap
        updated[.leftSingleTap] = .volumeUp
        link.onState?(state(keyMap: updated))
        await flush()
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.keyMap[.leftSingleTap], .volumeUp)
        XCTAssertFalse(model.writeFailed)
    }

    func testKeyFunctionRollsBackOnTimeout() async {
        let (model, link) = makeModel(writeTimeout: .milliseconds(40))
        link.onState?(state())
        await flush()

        model.choose(function: .lowLatency, for: .rightDoubleTap)
        XCTAssertEqual(model.keyMap[.rightDoubleTap], .lowLatency)

        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(model.pending)
        XCTAssertTrue(model.writeFailed)
        XCTAssertEqual(model.keyMap[.rightDoubleTap], .nextTrack)
    }

    func testDisconnectClearsPendingKeyWriteAndMap() async {
        let (model, link) = makeModel()
        link.onState?(state())
        await flush()

        model.choose(function: .volumeDown, for: .leftTripleTap)
        link.onDisconnect?()
        await flush()

        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertNil(model.pending)
        XCTAssertTrue(model.keyMap.isEmpty)
        XCTAssertFalse(model.writeFailed)
        XCTAssertTrue(model.areControlsDisabled)
    }

    func testKeyControlsNeverWriteWhenReadOnlyOrDisconnected() async {
        let (readOnlyModel, readOnlyLink) = makeModel(readOnly: true)
        readOnlyLink.onState?(state())
        await flush()
        readOnlyModel.choose(function: .volumeUp, for: .leftSingleTap)
        XCTAssertTrue(readOnlyLink.keyWrites.isEmpty)
        XCTAssertNil(readOnlyModel.pending)

        let (disconnectedModel, disconnectedLink) = makeModel()
        disconnectedModel.choose(function: .volumeUp, for: .leftSingleTap)
        XCTAssertTrue(disconnectedLink.keyWrites.isEmpty)
        XCTAssertNil(disconnectedModel.pending)
    }

    func testChangingOneCellPreservesOtherCells() async {
        let (model, link) = makeModel()
        link.onState?(state())
        await flush()

        model.choose(function: .lowLatency, for: .leftDoubleTap)
        XCTAssertEqual(model.keyMap[.leftDoubleTap], .lowLatency)
        XCTAssertEqual(model.keyMap[.leftSingleTap], .unassigned)
        XCTAssertEqual(model.keyMap[.rightSingleTap], .playPause)
        XCTAssertEqual(model.keyMap[.rightDoubleTap], .nextTrack)
        XCTAssertEqual(model.keyMap[.leftTripleTap], .ancMode)
        XCTAssertEqual(model.keyMap[.rightTripleTap], .voiceAssistant)

        var updated = Self.defaultKeyMap
        updated[.leftDoubleTap] = .lowLatency
        link.onState?(state(keyMap: updated))
        await flush()
        XCTAssertEqual(model.keyMap, updated)
    }

    func testChoosingSameFunctionDoesNotWrite() async {
        let (model, link) = makeModel()
        link.onState?(state())
        await flush()

        model.choose(function: .playPause, for: .rightSingleTap)
        XCTAssertTrue(link.keyWrites.isEmpty)
        XCTAssertNil(model.pending)
    }

    func testPollAndRetryRefreshKeyMap() async {
        let (model, link) = makeModel(writeTimeout: .milliseconds(20), pollInterval: .milliseconds(40))
        model.start()
        link.onState?(state())
        await flush()

        try? await Task.sleep(for: .milliseconds(90))
        XCTAssertGreaterThanOrEqual(link.refreshKeyMapCount, 1)

        let beforeRetry = link.refreshKeyMapCount
        model.retryAfterFailure()
        XCTAssertEqual(link.refreshKeyMapCount, beforeRetry + 1)
        model.stop()
    }
}
