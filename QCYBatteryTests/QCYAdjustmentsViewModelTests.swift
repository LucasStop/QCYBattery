import QCYKit
import XCTest
@testable import QCYBattery

private final class AdjustmentsFakeLink: QCYLink, @unchecked Sendable {
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
final class QCYAdjustmentsViewModelTests: XCTestCase {
    private static let defaultWear = QCYWearDetection(
        isEnabled: true,
        musicControl: .pauseOnly,
        isANCSwitchEnabled: true
    )

    private func makeModel(readOnly: Bool = false, writeTimeout: Duration = .seconds(5))
    -> (QCYViewModel, AdjustmentsFakeLink) {
        let link = AdjustmentsFakeLink()
        return (QCYViewModel(link: link, isReadOnly: readOnly, writeTimeout: writeTimeout), link)
    }

    private func state(
        powerOff: QCYPowerOff? = .fifteenMinutes,
        toneVolume: QCYToneVolume? = .medium,
        wearDetection: QCYWearDetection? = defaultWear
    ) -> QCYState {
        var state = QCYState()
        state.left = QCYBatteryLevel(raw: 90)
        state.right = QCYBatteryLevel(raw: 91)
        state.powerOff = powerOff
        state.toneVolume = toneVolume
        state.wearDetection = wearDetection
        return state
    }

    private func flush() async { try? await Task.sleep(for: .milliseconds(30)) }

    func testChoosingPowerOffSendsPacketAndConfirmsOnEcho() async {
        let (model, link) = makeModel()
        link.onState?(state(powerOff: .fifteenMinutes))
        await flush()

        model.choose(powerOff: .sixtyMinutes)
        XCTAssertEqual(link.sent, [.setPowerOff(.sixtyMinutes)])
        XCTAssertEqual(model.pending, .powerOff(.sixtyMinutes))
        XCTAssertEqual(model.powerOff, .sixtyMinutes)
        XCTAssertTrue(model.areControlsDisabled)

        // Estado antigo sem eco não confirma.
        link.onState?(state(powerOff: .fifteenMinutes))
        await flush()
        XCTAssertEqual(model.pending, .powerOff(.sixtyMinutes))

        link.onState?(state(powerOff: .sixtyMinutes))
        await flush()
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.powerOff, .sixtyMinutes)
        XCTAssertFalse(model.writeFailed)
    }

    func testChoosingToneVolumeSendsPacketAndConfirmsOnEcho() async {
        let (model, link) = makeModel()
        link.onState?(state(toneVolume: .medium))
        await flush()

        model.choose(toneVolume: .maximum)
        XCTAssertEqual(link.sent, [.setToneVolume(.maximum)])
        XCTAssertEqual(model.pending, .toneVolume(.maximum))
        XCTAssertEqual(model.toneVolume, .maximum)
        XCTAssertTrue(model.areControlsDisabled)

        link.onState?(state(toneVolume: .medium))
        await flush()
        XCTAssertEqual(model.pending, .toneVolume(.maximum))

        link.onState?(state(toneVolume: .maximum))
        await flush()
        XCTAssertNil(model.pending)
        XCTAssertEqual(model.toneVolume, .maximum)
        XCTAssertFalse(model.writeFailed)
    }

    func testWearDetectionPreservesOtherFieldsAndConfirmsOnEcho() async {
        let (model, link) = makeModel()
        let initial = QCYWearDetection(
            isEnabled: true,
            musicControl: .bothEarbuds,
            isANCSwitchEnabled: true
        )
        link.onState?(state(wearDetection: initial))
        await flush()
        XCTAssertTrue(model.isWearDetectionAvailable)
        XCTAssertTrue(model.isWearDetectionOn)

        model.setWearDetection(false)
        let expected = QCYWearDetection(
            isEnabled: false,
            musicControl: .bothEarbuds,
            isANCSwitchEnabled: true
        )
        XCTAssertEqual(link.sent, [.setWearDetection(expected)])
        XCTAssertEqual(model.pending, .wearDetection(false))
        XCTAssertFalse(model.isWearDetectionOn)
        XCTAssertTrue(model.areControlsDisabled)

        link.onState?(state(wearDetection: initial))
        await flush()
        XCTAssertEqual(model.pending, .wearDetection(false))

        link.onState?(state(wearDetection: expected))
        await flush()
        XCTAssertNil(model.pending)
        XCTAssertFalse(model.isWearDetectionOn)
        XCTAssertFalse(model.writeFailed)
    }

    func testWearDetectionDoesNotWriteWhenStateNotRead() async {
        let (model, link) = makeModel()
        link.onState?(state(wearDetection: nil))
        await flush()
        XCTAssertFalse(model.isWearDetectionAvailable)
        XCTAssertFalse(model.isWearDetectionOn)

        model.setWearDetection(true)
        XCTAssertTrue(link.sent.isEmpty)
        XCTAssertNil(model.pending)
    }

    func testAdjustmentsRollBackOnTimeout() async {
        let (model, link) = makeModel(writeTimeout: .milliseconds(40))
        link.onState?(state(powerOff: .thirtyMinutes, toneVolume: .lower, wearDetection: Self.defaultWear))
        await flush()

        model.choose(powerOff: .disabled)
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(model.pending)
        XCTAssertTrue(model.writeFailed)
        XCTAssertEqual(model.powerOff, .thirtyMinutes)

        model.choose(toneVolume: .higher)
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(model.pending)
        XCTAssertTrue(model.writeFailed)
        XCTAssertEqual(model.toneVolume, .lower)

        model.setWearDetection(false)
        try? await Task.sleep(for: .milliseconds(120))
        XCTAssertNil(model.pending)
        XCTAssertTrue(model.writeFailed)
        XCTAssertTrue(model.isWearDetectionOn)
    }

    func testChoosingSameValuesDoesNotWrite() async {
        let (model, link) = makeModel()
        link.onState?(state(powerOff: .ninetyMinutes, toneVolume: .higher, wearDetection: Self.defaultWear))
        await flush()

        model.choose(powerOff: .ninetyMinutes)
        model.choose(toneVolume: .higher)
        model.setWearDetection(true)
        XCTAssertTrue(link.sent.isEmpty)
        XCTAssertNil(model.pending)
    }

    func testAdjustmentControlsNeverWriteWhenReadOnlyOrDisconnected() async {
        let (readOnlyModel, readOnlyLink) = makeModel(readOnly: true)
        readOnlyLink.onState?(state())
        await flush()
        readOnlyModel.choose(powerOff: .disabled)
        readOnlyModel.choose(toneVolume: .maximum)
        readOnlyModel.setWearDetection(false)
        XCTAssertTrue(readOnlyLink.sent.isEmpty)
        XCTAssertNil(readOnlyModel.pending)

        let (disconnectedModel, disconnectedLink) = makeModel()
        disconnectedModel.choose(powerOff: .disabled)
        disconnectedModel.choose(toneVolume: .maximum)
        disconnectedModel.setWearDetection(false)
        XCTAssertTrue(disconnectedLink.sent.isEmpty)
        XCTAssertNil(disconnectedModel.pending)
    }

    func testDisconnectClearsPendingAdjustment() async {
        let (model, link) = makeModel()
        link.onState?(state())
        await flush()

        model.choose(powerOff: .disabled)
        link.onDisconnect?()
        await flush()

        XCTAssertEqual(model.phase, .disconnected)
        XCTAssertNil(model.pending)
        XCTAssertNil(model.powerOff)
        XCTAssertNil(model.toneVolume)
        XCTAssertFalse(model.isWearDetectionAvailable)
        XCTAssertFalse(model.writeFailed)
    }

    func testToneVolumeSliderIndexMapping() {
        XCTAssertEqual(QCYToneVolumeSlider.index(for: .lower), 0)
        XCTAssertEqual(QCYToneVolumeSlider.index(for: .medium), 1)
        XCTAssertEqual(QCYToneVolumeSlider.index(for: .higher), 2)
        XCTAssertEqual(QCYToneVolumeSlider.index(for: .maximum), 3)

        XCTAssertEqual(QCYToneVolumeSlider.volume(for: -1), .lower)
        XCTAssertEqual(QCYToneVolumeSlider.volume(for: 0), .lower)
        XCTAssertEqual(QCYToneVolumeSlider.volume(for: 1), .medium)
        XCTAssertEqual(QCYToneVolumeSlider.volume(for: 2), .higher)
        XCTAssertEqual(QCYToneVolumeSlider.volume(for: 3), .maximum)
        XCTAssertEqual(QCYToneVolumeSlider.volume(for: 9), .maximum)
    }
}
