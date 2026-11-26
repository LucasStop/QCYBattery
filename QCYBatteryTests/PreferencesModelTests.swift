import AppKit
import XCTest
@testable import QCYBattery

@MainActor
private final class FakeActivationPolicyApplier: ActivationPolicyApplying {
    private(set) var applied: [NSApplication.ActivationPolicy] = []

    func apply(_ policy: NSApplication.ActivationPolicy) {
        applied.append(policy)
    }
}

@MainActor
private final class FakeLaunchAtLoginController: LaunchAtLoginControlling {
    var isEnabled: Bool
    var shouldFail = false
    private(set) var calls: [Bool] = []

    init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    func setEnabled(_ enabled: Bool) throws {
        calls.append(enabled)
        if shouldFail {
            struct FakeError: Error {}
            throw FakeError()
        }
        isEnabled = enabled
    }
}

@MainActor
private final class FakePreferencesBatteryNotifier: BatteryNotifying {
    private(set) var authorizationRequests = 0
    private(set) var alerts: [BatteryAlert] = []

    func requestAuthorization() {
        authorizationRequests += 1
    }

    func notify(_ alert: BatteryAlert) {
        alerts.append(alert)
    }
}

@MainActor
final class PreferencesModelTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "com.lucasstop.QCYBatteryTests.prefs.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        super.tearDown()
    }

    private struct Fixture {
        let model: PreferencesModel
        let applier: FakeActivationPolicyApplier
        let login: FakeLaunchAtLoginController
        let notifier: FakePreferencesBatteryNotifier
    }

    private func makeFixture(loginEnabled: Bool = false) -> Fixture {
        let applier = FakeActivationPolicyApplier()
        let login = FakeLaunchAtLoginController(isEnabled: loginEnabled)
        let notifier = FakePreferencesBatteryNotifier()
        let model = PreferencesModel(
            defaults: defaults,
            policyApplier: applier,
            loginController: login,
            notifier: notifier
        )
        return Fixture(model: model, applier: applier, login: login, notifier: notifier)
    }

    func testDefaultsBothVisibilitiesOnAndRegularPolicy() {
        let fixture = makeFixture()
        XCTAssertTrue(fixture.model.showInMenuBar)
        XCTAssertTrue(fixture.model.showInDock)
        XCTAssertTrue(fixture.model.canTurnOffMenuBar)
        XCTAssertTrue(fixture.model.canTurnOffDock)
        XCTAssertEqual(fixture.model.activationPolicy, .regular)
    }

    func testTurningOffDockSwitchesToAccessoryAndBlocksTurningOffMenuBar() {
        let fixture = makeFixture()

        XCTAssertTrue(fixture.model.setShowInDock(false))
        XCTAssertFalse(fixture.model.showInDock)
        XCTAssertEqual(fixture.model.activationPolicy, .accessory)
        XCTAssertEqual(fixture.applier.applied, [.accessory])
        XCTAssertFalse(fixture.model.canTurnOffMenuBar)

        XCTAssertFalse(fixture.model.setShowInMenuBar(false))
        XCTAssertTrue(fixture.model.showInMenuBar)
    }

    func testTurningOffMenuBarBlocksTurningOffDock() {
        let fixture = makeFixture()

        XCTAssertTrue(fixture.model.setShowInMenuBar(false))
        XCTAssertFalse(fixture.model.showInMenuBar)
        XCTAssertFalse(fixture.model.canTurnOffDock)

        XCTAssertFalse(fixture.model.setShowInDock(false))
        XCTAssertTrue(fixture.model.showInDock)
        XCTAssertEqual(fixture.model.activationPolicy, .regular)
        XCTAssertTrue(fixture.applier.applied.isEmpty)
    }

    func testReenablingDockSwitchesBackToRegularPolicy() {
        let fixture = makeFixture()

        XCTAssertTrue(fixture.model.setShowInDock(false))
        XCTAssertTrue(fixture.model.setShowInDock(true))
        XCTAssertEqual(fixture.model.activationPolicy, .regular)
        XCTAssertEqual(fixture.applier.applied, [.accessory, .regular])
    }

    func testPreferencesPersistAcrossInstances() {
        let first = makeFixture()
        XCTAssertTrue(first.model.setShowInDock(false))

        let second = makeFixture()
        XCTAssertTrue(second.model.showInMenuBar)
        XCTAssertFalse(second.model.showInDock)
        XCTAssertEqual(second.model.activationPolicy, .accessory)

        second.model.applyActivationPolicy()
        XCTAssertEqual(second.applier.applied, [.accessory])
    }

    func testCorruptedBothFalseRecoversWithMenuBarOn() {
        defaults.set(false, forKey: "preferences.showInMenuBar")
        defaults.set(false, forKey: "preferences.showInDock")

        let fixture = makeFixture()
        XCTAssertTrue(fixture.model.showInMenuBar)
        XCTAssertFalse(fixture.model.showInDock)
        XCTAssertEqual(fixture.model.activationPolicy, .accessory)
    }

    func testLaunchAtLoginReflectsRealServiceStatus() {
        let fixture = makeFixture(loginEnabled: false)
        XCTAssertFalse(fixture.model.launchAtLogin)

        fixture.model.setLaunchAtLogin(true)
        XCTAssertTrue(fixture.model.launchAtLogin)
        XCTAssertEqual(fixture.login.calls, [true])

        fixture.login.shouldFail = true
        fixture.model.setLaunchAtLogin(false)
        XCTAssertTrue(fixture.model.launchAtLogin)

        fixture.login.isEnabled = false
        fixture.model.refreshLaunchAtLogin()
        XCTAssertFalse(fixture.model.launchAtLogin)
    }

    func testBatteryAlertsDefaultOnWithoutRequestingAuthorizationOnLaunch() {
        let fixture = makeFixture()
        XCTAssertTrue(fixture.model.lowBatteryAlertEnabled)
        XCTAssertTrue(fixture.model.criticalBatteryAlertEnabled)
        XCTAssertEqual(fixture.model.batteryAlertSettings, .allEnabled)
        XCTAssertEqual(fixture.notifier.authorizationRequests, 0)
    }

    func testBatteryAlertsPersistAcrossInstances() {
        let first = makeFixture()
        first.model.setLowBatteryAlert(false)
        first.model.setCriticalBatteryAlert(false)

        let second = makeFixture()
        XCTAssertFalse(second.model.lowBatteryAlertEnabled)
        XCTAssertFalse(second.model.criticalBatteryAlertEnabled)
        XCTAssertEqual(second.model.batteryAlertSettings, .allDisabled)
        XCTAssertEqual(second.notifier.authorizationRequests, 0)
    }

    func testTurningOnBatteryAlertRequestsAuthorizationOnce() {
        defaults.set(false, forKey: "preferences.lowBatteryAlert")
        defaults.set(false, forKey: "preferences.criticalBatteryAlert")
        let fixture = makeFixture()
        XCTAssertEqual(fixture.notifier.authorizationRequests, 0)

        fixture.model.setLowBatteryAlert(true)
        XCTAssertEqual(fixture.notifier.authorizationRequests, 1)

        fixture.model.setLowBatteryAlert(false)
        fixture.model.setLowBatteryAlert(true)
        fixture.model.setCriticalBatteryAlert(true)
        XCTAssertEqual(fixture.notifier.authorizationRequests, 1)
    }

    func testContextRuleDefaultsAndRoundTripPersistence() {
        let first = makeFixture()
        XCTAssertNil(first.model.globalANCHotKey)
        XCTAssertTrue(first.model.callRuleEnabled)
        XCTAssertEqual(first.model.callRuleScene, .transparency)
        XCTAssertEqual(first.model.contextRuleSettings, .default)

        let shortcut = MacroKeyShortcut(keyCode: 0, modifiers: [.command, .shift])
        first.model.setGlobalANCHotKey(shortcut)
        first.model.setCallRuleEnabled(false)
        first.model.setCallRuleScene(.normal)

        let second = makeFixture()
        XCTAssertEqual(second.model.globalANCHotKey, shortcut)
        XCTAssertFalse(second.model.callRuleEnabled)
        XCTAssertEqual(second.model.callRuleScene, .normal)
        XCTAssertEqual(
            second.model.contextRuleSettings,
            ContextRuleSettings(callEnabled: false, callScene: .normal)
        )

        second.model.setGlobalANCHotKey(nil)
        let third = makeFixture()
        XCTAssertNil(third.model.globalANCHotKey)
    }

    func testCorruptedGlobalHotKeyAndInvalidCallSceneRecoverToDefaults() {
        defaults.set(Data("not-json".utf8), forKey: "preferences.globalANCHotKey")
        defaults.set("unknown-scene", forKey: "preferences.contextRule.call.scene")

        let fixture = makeFixture()
        XCTAssertNil(fixture.model.globalANCHotKey)
        XCTAssertEqual(fixture.model.callRuleScene, .transparency)
    }
}
