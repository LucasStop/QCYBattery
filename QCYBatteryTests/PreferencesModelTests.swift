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
    }

    private func makeFixture(loginEnabled: Bool = false) -> Fixture {
        let applier = FakeActivationPolicyApplier()
        let login = FakeLaunchAtLoginController(isEnabled: loginEnabled)
        let model = PreferencesModel(defaults: defaults, policyApplier: applier, loginController: login)
        return Fixture(model: model, applier: applier, login: login)
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
}
