import QCYKit
import XCTest
@testable import QCYBattery

private final class SoundFakeLink: QCYLink, @unchecked Sendable {
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
final class QCYSoundViewModelTests: XCTestCase {
    private func makeModel(readOnly: Bool = false, writeTimeout: Duration = .seconds(5))
    -> (QCYViewModel, SoundFakeLink) {
        let link = SoundFakeLink()
        return (QCYViewModel(link: link, isReadOnly: readOnly, writeTimeout: writeTimeout), link)
    }

    private func state(
        scene: QCYANScene = .transparencyVocal,
        soundEffect: QCYSoundEffect? = .default,
        balance: UInt8? = 50
    ) -> QCYState {
        var state = QCYState()
        state.left = QCYBatteryLevel(raw: 90)
        state.right = QCYBatteryLevel(raw: 91)
        state.ancScene = scene
        state.soundEffect = soundEffect
        state.balance = balance
        return state
    }

    private func flush() async { try? await Task.sleep(for: .milliseconds(30)) }

    func testChoosingSoundEffectSendsPacketAndConfirmsOnEcho() async throws {
        let (model, link) = makeModel()
        link.onState?(state(soundEffect: .default))
        await flush()

        model.choose(effect: .heavyBass)
        let expected = try XCTUnwrap(QCYPacket.setSoundEffect(.heavyBass))
        XCTAssertEqual(link.sent, [expected])
        XCTAssertEqual(model.pending, .soundEffect(.heavyBass))
        XCTAssertEqual(model.soundEffect, .heavyBass)
        XCTAssertTrue(model.areControlsDisabled)

        link.onState?(state(soundEffect: .default))
        await flush()
        XCTAssertEqual(model.pending, .soundEffect(.heavyBass))

        link.onState?(state(soundEffect: .heavyBass))
        await flush()
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.soundEffect, .heavyBass)
        XCTAssertFalse(model.writeFailed)
    }

    func testChoosingUnmeasuredSoundEffectDoesNotWrite() async {
        let (model, link) = makeModel()
        link.onState?(state(soundEffect: .default))
        await flush()

        model.choose(effect: .unknown(0x05))
        XCTAssertTrue(link.sent.isEmpty)
        XCTAssertNil(model.pending)
    }

    func testSoundEffectRollsBackOnTimeout() async {
        let (model, link) = makeModel(writeTimeout: .milliseconds(40))
        link.onState?(state(soundEffect: .spatial))
        await flush()

        model.choose(effect: .pop)
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(model.pending)
        XCTAssertTrue(model.writeFailed)
        XCTAssertEqual(model.soundEffect, .spatial)
    }

    func testVocalBoostTogglesInTransparencyAndRestoresLastLevel() async {
        let (model, link) = makeModel()
        link.onState?(state(scene: .transparency(level: 5)))
        await flush()
        XCTAssertTrue(model.isVocalBoostAvailable)
        XCTAssertFalse(model.isVocalBoostOn)

        model.setVocalBoost(true)
        XCTAssertEqual(link.sent, [.transparencyVocal()])
        XCTAssertEqual(model.pending, .vocalBoost(true))
        XCTAssertTrue(model.isVocalBoostOn)

        link.onState?(state(scene: .transparencyVocal))
        await flush()
        XCTAssertNil(model.pending)
        XCTAssertTrue(model.isVocalBoostOn)

        model.setVocalBoost(false)
        XCTAssertEqual(link.sent.last, .transparency(level: 5))
        XCTAssertEqual(model.pending, .vocalBoost(false))
        XCTAssertFalse(model.isVocalBoostOn)

        link.onState?(state(scene: .transparency(level: 5)))
        await flush()
        XCTAssertNil(model.pending)
        XCTAssertFalse(model.isVocalBoostOn)
    }

    func testVocalBoostFallsBackToLevelThreeWhenUnknown() async {
        let (model, link) = makeModel()
        link.onState?(state(scene: .transparencyVocal))
        await flush()

        model.setVocalBoost(false)
        XCTAssertEqual(link.sent, [.transparency(level: 3)])
    }

    func testVocalBoostOutsideTransparencyDoesNotWrite() async {
        let (model, link) = makeModel()
        link.onState?(state(scene: .ancAdaptive))
        await flush()
        XCTAssertFalse(model.isVocalBoostAvailable)
        XCTAssertFalse(model.isVocalBoostOn)

        model.setVocalBoost(true)
        XCTAssertTrue(link.sent.isEmpty)
        XCTAssertNil(model.pending)

        link.onState?(state(scene: .normal))
        await flush()
        XCTAssertFalse(model.isVocalBoostAvailable)

        model.setVocalBoost(true)
        XCTAssertTrue(link.sent.isEmpty)
        XCTAssertNil(model.pending)
    }

    func testBalanceWritesOnCommitClampsAndResets() async {
        let (model, link) = makeModel()
        link.onState?(state(balance: 50))
        await flush()
        XCTAssertEqual(model.balance, 50)

        model.setBalance(150)
        XCTAssertEqual(link.sent, [.setBalance(100)])
        XCTAssertEqual(model.pending, .balance(100))
        XCTAssertEqual(model.balance, 100)

        link.onState?(state(balance: 100))
        await flush()
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.balance, 100)

        model.setBalance(50)
        XCTAssertEqual(link.sent.last, .setBalance(50))
        XCTAssertEqual(model.pending, .balance(50))
        XCTAssertEqual(model.balance, 50)

        link.onState?(state(balance: 50))
        await flush()
        XCTAssertNil(model.pending)

        model.setBalance(50)
        XCTAssertEqual(link.sent.count, 2)
    }

    func testBalanceOffsetFormatting() {
        XCTAssertNil(QCYBalanceSlider.formattedOffset(for: 50))
        XCTAssertEqual(QCYBalanceSlider.formattedOffset(for: 0), "L 100")
        XCTAssertEqual(QCYBalanceSlider.formattedOffset(for: 42), "L 16")
        XCTAssertEqual(QCYBalanceSlider.formattedOffset(for: 58), "R 16")
        XCTAssertEqual(QCYBalanceSlider.formattedOffset(for: 100), "R 100")
        XCTAssertEqual(QCYBalanceSlider.formattedOffset(for: 140), "R 100")
    }

    func testSoundControlsNeverWriteWhenReadOnlyOrDisconnected() async {
        let (readOnlyModel, readOnlyLink) = makeModel(readOnly: true)
        readOnlyLink.onState?(state(soundEffect: .default, balance: 50))
        await flush()
        readOnlyModel.choose(effect: .spatial)
        readOnlyModel.setVocalBoost(false)
        readOnlyModel.setBalance(75)
        XCTAssertTrue(readOnlyLink.sent.isEmpty)
        XCTAssertNil(readOnlyModel.pending)

        let (disconnectedModel, disconnectedLink) = makeModel()
        disconnectedModel.choose(effect: .spatial)
        disconnectedModel.setVocalBoost(true)
        disconnectedModel.setBalance(25)
        XCTAssertTrue(disconnectedLink.sent.isEmpty)
        XCTAssertNil(disconnectedModel.pending)
    }
}
