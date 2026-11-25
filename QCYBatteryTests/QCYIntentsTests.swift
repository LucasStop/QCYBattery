import QCYKit
import XCTest
@testable import QCYBattery

private final class IntentFakeLink: QCYLink, @unchecked Sendable {
    var onState: (@Sendable (QCYState) -> Void)?
    var onAdvertisement: (@Sendable (QCYAdvertisement) -> Void)?
    var onReady: (@Sendable () -> Void)?
    var onDisconnect: (@Sendable () -> Void)?
    private(set) var sent: [QCYPacket] = []

    func start() {}
    func stop() {}
    func refresh() {}
    func refreshKeyMap() {}
    func send(_ packet: QCYPacket) { sent.append(packet) }
    func setKeyFunction(_ function: QCYKeyFunction, for gesture: QCYGesture) {}
}

@MainActor
final class QCYIntentsTests: XCTestCase {
    private func makeModel(
        readOnly: Bool = false,
        writeTimeout: Duration = .milliseconds(80)
    ) -> (QCYViewModel, IntentFakeLink) {
        let link = IntentFakeLink()
        let model = QCYViewModel(link: link, isReadOnly: readOnly, writeTimeout: writeTimeout)
        return (model, link)
    }

    private func makeRunner(
        model: QCYViewModel,
        connectionTimeout: Duration = .milliseconds(120),
        writeTimeout: Duration = .milliseconds(200)
    ) -> QCYIntentRunner {
        QCYIntentRunner(
            model: model,
            connectionTimeout: connectionTimeout,
            writeTimeout: writeTimeout,
            pollInterval: .milliseconds(10)
        )
    }

    private func state(
        left: UInt8? = 90,
        right: UInt8? = 91,
        anc: UInt8 = 0x03,
        soundEffect: QCYSoundEffect? = .default
    ) -> QCYState {
        var snapshot = QCYState()
        snapshot.left = left.map { QCYBatteryLevel(raw: $0) }
        snapshot.right = right.map { QCYBatteryLevel(raw: $0) }
        snapshot.ancScene = QCYANScene(mode: anc, subScene: 0x02, noiseValue: 0x00)
        snapshot.soundEffect = soundEffect
        return snapshot
    }

    private func flush() async {
        try? await Task.sleep(for: .milliseconds(25))
    }

    private func assertThrows(
        _ expected: QCYIntentError,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as QCYIntentError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Unexpected error: \(error)", file: file, line: line)
        }
    }

    // MARK: - Modo de ruído

    func testSetNoiseModeConfirmsOnEcho() async throws {
        let (model, link) = makeModel(writeTimeout: .seconds(1))
        link.onState?(state(anc: 0x03))
        await flush()

        let runner = makeRunner(model: model, writeTimeout: .seconds(1))
        let echoTask = Task {
            try? await Task.sleep(for: .milliseconds(30))
            link.onState?(state(anc: 0x01))
        }

        try await runner.setNoiseMode(.anc)
        await echoTask.value

        XCTAssertEqual(link.sent, [QCYANCChoice.anc.packet])
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.ancChoice, .anc)
        XCTAssertFalse(model.writeFailed)
    }

    func testSetNoiseModeWaitsForConnectionBeforeWriting() async throws {
        let (model, link) = makeModel(writeTimeout: .seconds(1))
        let runner = makeRunner(model: model, connectionTimeout: .milliseconds(300), writeTimeout: .seconds(1))

        let linkTask = Task {
            try? await Task.sleep(for: .milliseconds(30))
            link.onState?(state(anc: 0x02))
            try? await Task.sleep(for: .milliseconds(40))
            link.onState?(state(anc: 0x03))
        }

        try await runner.setNoiseMode(.transparency)
        await linkTask.value

        XCTAssertEqual(link.sent, [QCYANCChoice.transparency.packet])
        XCTAssertEqual(model.ancChoice, .transparency)
    }

    func testSetNoiseModeFailsAfterConnectionTimeout() async {
        let (model, link) = makeModel()
        let runner = makeRunner(model: model, connectionTimeout: .milliseconds(60))

        await assertThrows(.notConnected) { try await runner.setNoiseMode(.anc) }
        XCTAssertTrue(link.sent.isEmpty)
    }

    func testSetNoiseModeFailsWhenEarbudsDoNotEcho() async {
        let (model, link) = makeModel(writeTimeout: .milliseconds(40))
        link.onState?(state(anc: 0x03))
        await flush()

        let runner = makeRunner(model: model, writeTimeout: .milliseconds(250))

        await assertThrows(.writeFailed) { try await runner.setNoiseMode(.normal) }
        XCTAssertEqual(link.sent, [QCYANCChoice.normal.packet])
        XCTAssertTrue(model.writeFailed)
        XCTAssertEqual(model.ancChoice, .transparency)
    }

    func testSetNoiseModeFailsWhenLinkDisconnectsDuringWrite() async {
        let (model, link) = makeModel(writeTimeout: .seconds(1))
        link.onState?(state(anc: 0x03))
        await flush()

        let runner = makeRunner(model: model, writeTimeout: .seconds(1))
        let disconnectTask = Task {
            try? await Task.sleep(for: .milliseconds(30))
            link.onDisconnect?()
        }

        await assertThrows(.notConnected) { try await runner.setNoiseMode(.anc) }
        await disconnectTask.value
    }

    func testSetNoiseModeIsIdempotentWhenAlreadyActive() async throws {
        let (model, link) = makeModel()
        link.onState?(state(anc: 0x01))
        await flush()

        let runner = makeRunner(model: model)
        try await runner.setNoiseMode(.anc)

        XCTAssertTrue(link.sent.isEmpty)
        XCTAssertNil(model.pending)
    }

    func testSetNoiseModeNeverWritesInReadOnlyMode() async {
        let (model, link) = makeModel(readOnly: true)
        link.onState?(state(anc: 0x03))
        await flush()

        let runner = makeRunner(model: model)
        await assertThrows(.readOnly) { try await runner.setNoiseMode(.anc) }
        XCTAssertTrue(link.sent.isEmpty)
        XCTAssertNil(model.pending)
    }

    // MARK: - Efeito de som

    func testSetSoundEffectConfirmsOnEcho() async throws {
        let (model, link) = makeModel(writeTimeout: .seconds(1))
        link.onState?(state(soundEffect: .default))
        await flush()

        let runner = makeRunner(model: model, writeTimeout: .seconds(1))
        let echoTask = Task {
            try? await Task.sleep(for: .milliseconds(30))
            link.onState?(state(soundEffect: .heavyBass))
        }

        try await runner.setSoundEffect(.heavyBass)
        await echoTask.value

        let expected = try XCTUnwrap(QCYPacket.setSoundEffect(.heavyBass))
        XCTAssertEqual(link.sent, [expected])
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.soundEffect, .heavyBass)
    }

    func testSetSoundEffectFailsWithoutEcho() async {
        let (model, link) = makeModel(writeTimeout: .milliseconds(40))
        link.onState?(state(soundEffect: .spatial))
        await flush()

        let runner = makeRunner(model: model, writeTimeout: .milliseconds(250))

        await assertThrows(.writeFailed) { try await runner.setSoundEffect(.pop) }
        XCTAssertTrue(model.writeFailed)
        XCTAssertEqual(model.soundEffect, .spatial)
    }

    func testSetSoundEffectNeverWritesInReadOnlyMode() async {
        let (model, link) = makeModel(readOnly: true)
        link.onState?(state(soundEffect: .default))
        await flush()

        let runner = makeRunner(model: model)
        await assertThrows(.readOnly) { try await runner.setSoundEffect(.spatial) }
        XCTAssertTrue(link.sent.isEmpty)
    }

    // MARK: - Bateria

    func testReadBatteryReturnsSummaryAndSidePercentages() async throws {
        let (model, link) = makeModel()
        link.onState?(state(left: 88, right: 92))
        await flush()

        let runner = makeRunner(model: model)
        let status = try await runner.readBattery()

        XCTAssertEqual(status.summary, "L 88% · R 92%")
        XCTAssertEqual(status.leftPercent, 88)
        XCTAssertEqual(status.rightPercent, 92)
    }

    func testReadBatteryKeepsMissingSideNilWithoutFakingZero() async throws {
        let (model, link) = makeModel()
        link.onState?(state(left: 74, right: nil))
        await flush()

        let runner = makeRunner(model: model)
        let status = try await runner.readBattery()

        XCTAssertEqual(status.summary, "L 74% · R —")
        XCTAssertEqual(status.leftPercent, 74)
        XCTAssertNil(status.rightPercent)
    }

    func testReadBatterySucceedsInReadOnlyMode() async throws {
        let (model, link) = makeModel(readOnly: true)
        link.onState?(state(left: 65, right: 70))
        await flush()

        let runner = makeRunner(model: model)
        let status = try await runner.readBattery()

        XCTAssertEqual(status.summary, "L 65% · R 70%")
        XCTAssertEqual(status.leftPercent, 65)
        XCTAssertEqual(status.rightPercent, 70)
    }

    func testReadBatteryWaitsForConnectionBeforeReturning() async throws {
        let (model, link) = makeModel()
        let runner = makeRunner(model: model, connectionTimeout: .milliseconds(300))

        let connectTask = Task {
            try? await Task.sleep(for: .milliseconds(30))
            link.onState?(state(left: 55, right: 60))
        }

        let status = try await runner.readBattery()
        await connectTask.value

        XCTAssertEqual(status.summary, "L 55% · R 60%")
        XCTAssertEqual(status.leftPercent, 55)
        XCTAssertEqual(status.rightPercent, 60)
    }

    func testReadBatteryFailsWithoutConnection() async {
        let (model, _) = makeModel()
        let runner = makeRunner(model: model, connectionTimeout: .milliseconds(60))

        await assertThrows(.notConnected) { _ = try await runner.readBattery() }
    }

    // MARK: - Mapeamento dos AppEnums

    func testAppEnumsMapEverySupportedOption() {
        XCTAssertEqual(QCYNoiseModeAppEnum.anc.choice, .anc)
        XCTAssertEqual(QCYNoiseModeAppEnum.normal.choice, .normal)
        XCTAssertEqual(QCYNoiseModeAppEnum.transparency.choice, .transparency)

        XCTAssertEqual(QCYSoundEffectAppEnum.spatial.soundEffect, .spatial)
        XCTAssertEqual(QCYSoundEffectAppEnum.standard.soundEffect, .default)
        XCTAssertEqual(QCYSoundEffectAppEnum.pop.soundEffect, .pop)
        XCTAssertEqual(QCYSoundEffectAppEnum.heavyBass.soundEffect, .heavyBass)
    }
}
