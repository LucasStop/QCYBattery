import QCYKit
import XCTest
@testable import QCYBattery

private final class FakeAlertLink: QCYLink, @unchecked Sendable {
    var onState: (@Sendable (QCYState) -> Void)?
    var onAdvertisement: (@Sendable (QCYAdvertisement) -> Void)?
    var onReady: (@Sendable () -> Void)?
    var onDisconnect: (@Sendable () -> Void)?

    func start() {}
    func stop() {}
    func refresh() {}
    func refreshKeyMap() {}
    func send(_ packet: QCYPacket) {}
    func setKeyFunction(_ function: QCYKeyFunction, for gesture: QCYGesture) {}
}

@MainActor
private final class FakeBatteryNotifier: BatteryNotifying {
    private(set) var authorizationRequests = 0
    private(set) var alerts: [BatteryAlert] = []

    func requestAuthorization() {
        authorizationRequests += 1
    }

    func notify(_ alert: BatteryAlert) {
        alerts.append(alert)
    }
}

final class BatteryAlertPolicyTests: XCTestCase {
    private func level(_ percent: Int, charging: Bool = false) -> QCYBatteryLevel {
        let clamped = UInt8(min(max(percent, 0), 100))
        return QCYBatteryLevel(raw: charging ? (0x80 | clamped) : clamped)
    }

    func testCrossesLowThresholdTriggersOnceAndDoesNotRepeat() {
        var policy = BatteryAlertPolicy()

        XCTAssertTrue(policy.evaluate(left: level(25), right: level(80), settings: .allEnabled).isEmpty)

        let first = policy.evaluate(left: level(20), right: level(80), settings: .allEnabled)
        XCTAssertEqual(first, [BatteryAlert(side: .left, severity: .low, percent: 20)])

        XCTAssertTrue(policy.evaluate(left: level(18), right: level(80), settings: .allEnabled).isEmpty)
        XCTAssertTrue(policy.evaluate(left: level(20), right: level(80), settings: .allEnabled).isEmpty)
    }

    func testCrossesCriticalThresholdTriggersOnceAndDoesNotRepeat() {
        var policy = BatteryAlertPolicy()

        _ = policy.evaluate(left: level(19), right: level(80), settings: .allEnabled)

        let critical = policy.evaluate(left: level(10), right: level(80), settings: .allEnabled)
        XCTAssertEqual(critical, [BatteryAlert(side: .left, severity: .critical, percent: 10)])

        XCTAssertTrue(policy.evaluate(left: level(8), right: level(80), settings: .allEnabled).isEmpty)
        XCTAssertTrue(policy.evaluate(left: level(10), right: level(80), settings: .allEnabled).isEmpty)
    }

    func testBothThresholdsCrossedInSameEventCriticalWinsAndSuppressesLow() {
        var policy = BatteryAlertPolicy()

        let alerts = policy.evaluate(left: level(8), right: level(90), settings: .allEnabled)
        XCTAssertEqual(alerts, [BatteryAlert(side: .left, severity: .critical, percent: 8)])

        // Permanece abaixo da histerese de 20% (25%): não dispara aviso atrasado de 20%.
        XCTAssertTrue(policy.evaluate(left: level(12), right: level(90), settings: .allEnabled).isEmpty)
    }

    func testRearmsWhenCharging() {
        var policy = BatteryAlertPolicy()

        XCTAssertEqual(
            policy.evaluate(left: level(20), right: level(80), settings: .allEnabled),
            [BatteryAlert(side: .left, severity: .low, percent: 20)]
        )
        XCTAssertEqual(
            policy.evaluate(left: level(10), right: level(80), settings: .allEnabled),
            [BatteryAlert(side: .left, severity: .critical, percent: 10)]
        )

        // Carregando: não notifica e rearma ambos os limites.
        XCTAssertTrue(policy.evaluate(left: level(10, charging: true), right: level(80), settings: .allEnabled).isEmpty)

        XCTAssertEqual(
            policy.evaluate(left: level(20), right: level(80), settings: .allEnabled),
            [BatteryAlert(side: .left, severity: .low, percent: 20)]
        )
        XCTAssertEqual(
            policy.evaluate(left: level(10), right: level(80), settings: .allEnabled),
            [BatteryAlert(side: .left, severity: .critical, percent: 10)]
        )
    }

    func testRearmsOnlyAboveHysteresisThreshold() {
        var policy = BatteryAlertPolicy()

        XCTAssertEqual(
            policy.evaluate(left: level(20), right: level(80), settings: .allEnabled),
            [BatteryAlert(side: .left, severity: .low, percent: 20)]
        )
        // 25% == 20 + 5: ainda não rearma (precisa subir ACIMA de limite + 5).
        XCTAssertTrue(policy.evaluate(left: level(25), right: level(80), settings: .allEnabled).isEmpty)
        XCTAssertTrue(policy.evaluate(left: level(20), right: level(80), settings: .allEnabled).isEmpty)

        // 26% > 25: rearma aviso de 20%.
        XCTAssertTrue(policy.evaluate(left: level(26), right: level(80), settings: .allEnabled).isEmpty)
        XCTAssertEqual(
            policy.evaluate(left: level(19), right: level(80), settings: .allEnabled),
            [BatteryAlert(side: .left, severity: .low, percent: 19)]
        )

        // Crítico (10%): histerese em 15%, só rearma em 16%+.
        XCTAssertEqual(
            policy.evaluate(left: level(10), right: level(80), settings: .allEnabled),
            [BatteryAlert(side: .left, severity: .critical, percent: 10)]
        )
        XCTAssertTrue(policy.evaluate(left: level(15), right: level(80), settings: .allEnabled).isEmpty)
        XCTAssertTrue(policy.evaluate(left: level(10), right: level(80), settings: .allEnabled).isEmpty)

        XCTAssertTrue(policy.evaluate(left: level(16), right: level(80), settings: .allEnabled).isEmpty)
        XCTAssertEqual(
            policy.evaluate(left: level(9), right: level(80), settings: .allEnabled),
            [BatteryAlert(side: .left, severity: .critical, percent: 9)]
        )
    }

    func testNilAndZeroLevelsAreIgnoredWithoutRearming() {
        var policy = BatteryAlertPolicy()

        XCTAssertTrue(policy.evaluate(left: nil, right: QCYBatteryLevel(raw: 0), settings: .allEnabled).isEmpty)

        XCTAssertEqual(
            policy.evaluate(left: level(20), right: nil, settings: .allEnabled),
            [BatteryAlert(side: .left, severity: .low, percent: 20)]
        )

        // Leitura ausente ou 0 no meio não rearma o lado já disparado.
        XCTAssertTrue(policy.evaluate(left: nil, right: nil, settings: .allEnabled).isEmpty)
        XCTAssertTrue(policy.evaluate(left: QCYBatteryLevel(raw: 0), right: nil, settings: .allEnabled).isEmpty)
        XCTAssertTrue(policy.evaluate(left: level(19), right: nil, settings: .allEnabled).isEmpty)
    }

    func testDisabledSwitchesDoNotNotify() {
        var policy = BatteryAlertPolicy()

        let onlyCritical = BatteryAlertSettings(lowEnabled: false, criticalEnabled: true)
        XCTAssertTrue(policy.evaluate(left: level(20), right: level(80), settings: onlyCritical).isEmpty)
        XCTAssertEqual(
            policy.evaluate(left: level(10), right: level(80), settings: onlyCritical),
            [BatteryAlert(side: .left, severity: .critical, percent: 10)]
        )

        let onlyLow = BatteryAlertSettings(lowEnabled: true, criticalEnabled: false)
        XCTAssertEqual(
            policy.evaluate(left: level(80), right: level(8), settings: onlyLow),
            [BatteryAlert(side: .right, severity: .low, percent: 8)]
        )

        XCTAssertTrue(policy.evaluate(left: level(5), right: level(5), settings: .allDisabled).isEmpty)
    }

    func testSidesAreTrackedIndependently() {
        var policy = BatteryAlertPolicy()

        XCTAssertEqual(
            policy.evaluate(left: level(20), right: level(85), settings: .allEnabled),
            [BatteryAlert(side: .left, severity: .low, percent: 20)]
        )
        XCTAssertEqual(
            policy.evaluate(left: level(18), right: level(10), settings: .allEnabled),
            [BatteryAlert(side: .right, severity: .critical, percent: 10)]
        )
    }

    @MainActor
    func testNotificationContentIncludesPercentAndHasNoMAC() {
        let content = UNBatteryNotifier.content(for: BatteryAlert(side: .left, severity: .low, percent: 18))
        XCTAssertFalse(content.title.isEmpty)
        XCTAssertTrue(content.body.contains("18%"))
        XCTAssertFalse(content.body.contains(":"))
    }
}

@MainActor
final class QCYViewModelBatteryAlertsTests: XCTestCase {
    private func flush() async {
        try? await Task.sleep(for: .milliseconds(30))
    }

    private func state(left: UInt8?, right: UInt8?) -> QCYState {
        var state = QCYState()
        state.left = left.map(QCYBatteryLevel.init(raw:))
        state.right = right.map(QCYBatteryLevel.init(raw:))
        return state
    }

    func testViewModelNotifiesViaFakeWhenBatteryCrossesThresholds() async {
        let link = FakeAlertLink()
        let notifier = FakeBatteryNotifier()
        let model = QCYViewModel(link: link, notifier: notifier, alertSettings: { .allEnabled })

        link.onState?(state(left: 80, right: 85))
        await flush()
        XCTAssertTrue(notifier.alerts.isEmpty)

        link.onState?(state(left: 20, right: 85))
        await flush()
        XCTAssertEqual(notifier.alerts, [BatteryAlert(side: .left, severity: .low, percent: 20)])

        link.onState?(state(left: 18, right: 85))
        await flush()
        XCTAssertEqual(notifier.alerts.count, 1)

        link.onState?(state(left: 10, right: 85))
        await flush()
        XCTAssertEqual(notifier.alerts, [
            BatteryAlert(side: .left, severity: .low, percent: 20),
            BatteryAlert(side: .left, severity: .critical, percent: 10)
        ])
        _ = model
    }

    func testViewModelRespectsAlertSettings() async {
        let link = FakeAlertLink()
        let notifier = FakeBatteryNotifier()
        var currentSettings = BatteryAlertSettings(lowEnabled: false, criticalEnabled: true)
        let model = QCYViewModel(link: link, notifier: notifier, alertSettings: { currentSettings })

        link.onState?(state(left: 20, right: 80))
        await flush()
        XCTAssertTrue(notifier.alerts.isEmpty)

        link.onState?(state(left: 9, right: 80))
        await flush()
        XCTAssertEqual(notifier.alerts, [BatteryAlert(side: .left, severity: .critical, percent: 9)])

        currentSettings.criticalEnabled = false
        link.onState?(state(left: 9, right: 8))
        await flush()
        XCTAssertEqual(notifier.alerts.count, 1)
        _ = model
    }

    func testViewModelDoesNotRepeatAfterBriefDisconnect() async {
        let link = FakeAlertLink()
        let notifier = FakeBatteryNotifier()
        let model = QCYViewModel(link: link, notifier: notifier, alertSettings: { .allEnabled })

        link.onState?(state(left: 20, right: 80))
        await flush()
        XCTAssertEqual(notifier.alerts.count, 1)

        link.onDisconnect?()
        await flush()

        link.onState?(state(left: 19, right: 80))
        await flush()
        XCTAssertEqual(notifier.alerts.count, 1)

        link.onState?(state(left: 0x80 | 20, right: 80))
        await flush()
        link.onState?(state(left: 20, right: 80))
        await flush()
        XCTAssertEqual(notifier.alerts.count, 2)
        _ = model
    }
}
