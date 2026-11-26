import Carbon.HIToolbox
import QCYKit
import XCTest
@testable import QCYBattery

private final class ContextFakeLink: QCYLink, @unchecked Sendable {
    var onState: (@Sendable (QCYState) -> Void)?
    var onAdvertisement: (@Sendable (QCYAdvertisement) -> Void)?
    var onReady: (@Sendable () -> Void)?
    var onDisconnect: (@Sendable () -> Void)?
    private(set) var sent: [QCYPacket] = []
    var autoEchoANC = false

    func start() {}
    func stop() {}
    func refresh() {}
    func refreshKeyMap() {}
    func setKeyFunction(_ function: QCYKeyFunction, for gesture: QCYGesture) {}

    func send(_ packet: QCYPacket) {
        sent.append(packet)
        if autoEchoANC, let choice = QCYANCChoice.allCases.first(where: { $0.packet == packet }) {
            let mode: UInt8 = switch choice {
            case .anc: 0x01
            case .normal: 0x02
            case .transparency: 0x03
            }
            var snapshot = QCYState()
            snapshot.left = QCYBatteryLevel(raw: 90)
            snapshot.right = QCYBatteryLevel(raw: 91)
            snapshot.ancScene = QCYANScene(mode: mode, subScene: 0x02, noiseValue: 0x00)
            onState?(snapshot)
        }
    }
}

@MainActor
private final class FakeGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    var onTrigger: (@MainActor () -> Void)?
    private(set) var registered: [MacroKeyShortcut] = []
    private(set) var unregisterCount = 0
    var errorToThrow: GlobalHotKeyError?

    func register(_ shortcut: MacroKeyShortcut) throws {
        if let error = errorToThrow {
            throw error
        }
        registered.append(shortcut)
    }

    func unregister() {
        unregisterCount += 1
    }

    func simulateTrigger() {
        onTrigger?()
    }
}

@MainActor
private final class FakeCallActivityMonitor: CallActivityMonitoring {
    private(set) var isActive = false
    var onChange: (@MainActor (Bool) -> Void)?
    private(set) var startCount = 0
    private(set) var stopCount = 0

    func start() {
        startCount += 1
    }

    func stop() {
        stopCount += 1
        isActive = false
    }

    func simulateCall(_ active: Bool) {
        isActive = active
        onChange?(active)
    }
}

@MainActor
private final class FakeContextActivationPolicy: ActivationPolicyApplying {
    func apply(_ policy: NSApplication.ActivationPolicy) {}
}

@MainActor
private final class FakeContextLoginController: LaunchAtLoginControlling {
    var isEnabled = false
    func setEnabled(_ enabled: Bool) throws { isEnabled = enabled }
}

@MainActor
final class ContextRuleCoordinatorTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        try await super.setUp()
        suiteName = "com.lucasstop.QCYBatteryTests.context.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        suiteName = nil
        try await super.tearDown()
    }

    private struct Fixture {
        let model: QCYViewModel
        let link: ContextFakeLink
        let preferences: PreferencesModel
        let hotKey: FakeGlobalHotKeyRegistrar
        let callMonitor: FakeCallActivityMonitor
        let coordinator: ContextRuleCoordinator
    }

    private func makeFixture(
        readOnly: Bool = false,
        callRuleEnabled: Bool = true,
        callRuleScene: QCYANCChoice = .transparency,
        storedHotKey: MacroKeyShortcut? = nil
    ) -> Fixture {
        defaults.set(callRuleEnabled, forKey: "preferences.contextRule.call.enabled")
        defaults.set(callRuleScene.rawValue, forKey: "preferences.contextRule.call.scene")
        if let storedHotKey, let data = try? JSONEncoder().encode(storedHotKey) {
            defaults.set(data, forKey: "preferences.globalANCHotKey")
        }

        let link = ContextFakeLink()
        let model = QCYViewModel(link: link, isReadOnly: readOnly, writeTimeout: .seconds(1))
        let preferences = PreferencesModel(
            defaults: defaults,
            policyApplier: FakeContextActivationPolicy(),
            loginController: FakeContextLoginController(),
            notifier: NoOpBatteryNotifier()
        )
        let hotKey = FakeGlobalHotKeyRegistrar()
        let callMonitor = FakeCallActivityMonitor()
        let coordinator = ContextRuleCoordinator(
            model: model,
            preferences: preferences,
            hotKeyRegistrar: hotKey,
            callMonitor: callMonitor,
            runnerFactory: { viewModel in
                QCYIntentRunner(
                    model: viewModel,
                    connectionTimeout: .milliseconds(120),
                    writeTimeout: .milliseconds(250),
                    pollInterval: .milliseconds(10)
                )
            }
        )
        return Fixture(
            model: model,
            link: link,
            preferences: preferences,
            hotKey: hotKey,
            callMonitor: callMonitor,
            coordinator: coordinator
        )
    }

    private func ancState(_ mode: UInt8) -> QCYState {
        var snapshot = QCYState()
        snapshot.left = QCYBatteryLevel(raw: 90)
        snapshot.right = QCYBatteryLevel(raw: 91)
        snapshot.ancScene = QCYANScene(mode: mode, subScene: 0x02, noiseValue: 0x00)
        return snapshot
    }

    private func flush(_ duration: Duration = .milliseconds(40)) async {
        try? await Task.sleep(for: duration)
    }

    // MARK: - Atalho global

    func testGlobalHotKeyCyclesANCTransparencyNormalANC() async {
        let shortcut = MacroKeyShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command, .shift])
        let fixture = makeFixture(callRuleEnabled: false, storedHotKey: shortcut)
        fixture.coordinator.start()

        fixture.link.onState?(ancState(0x01)) // ANC
        await flush()

        fixture.hotKey.simulateTrigger()
        XCTAssertEqual(fixture.link.sent, [QCYANCChoice.transparency.packet])
        fixture.link.onState?(ancState(0x03)) // Transparência
        await flush()

        fixture.hotKey.simulateTrigger()
        XCTAssertEqual(fixture.link.sent, [QCYANCChoice.transparency.packet, QCYANCChoice.normal.packet])
        fixture.link.onState?(ancState(0x02)) // Normal
        await flush()

        fixture.hotKey.simulateTrigger()
        XCTAssertEqual(
            fixture.link.sent,
            [QCYANCChoice.transparency.packet, QCYANCChoice.normal.packet, QCYANCChoice.anc.packet]
        )
    }

    func testGlobalHotKeyDoesNothingWhenDisconnectedOrReadOnly() async {
        let shortcut = MacroKeyShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command, .shift])
        let disconnected = makeFixture(callRuleEnabled: false, storedHotKey: shortcut)
        disconnected.coordinator.start()
        disconnected.link.onDisconnect?()
        await flush()

        disconnected.hotKey.simulateTrigger()
        XCTAssertTrue(disconnected.link.sent.isEmpty)
        XCTAssertFalse(disconnected.model.writeFailed)

        let readOnly = makeFixture(readOnly: true, callRuleEnabled: false, storedHotKey: shortcut)
        readOnly.coordinator.start()
        readOnly.link.onState?(ancState(0x01))
        await flush()

        readOnly.hotKey.simulateTrigger()
        XCTAssertTrue(readOnly.link.sent.isEmpty)
        XCTAssertFalse(readOnly.model.writeFailed)
    }

    func testGlobalHotKeyConflictShowsErrorAndKeepsPreviousShortcut() {
        let previous = MacroKeyShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command, .shift])
        let conflicting = MacroKeyShortcut(keyCode: UInt16(kVK_ANSI_S), modifiers: [.command, .shift])
        let fixture = makeFixture(callRuleEnabled: false, storedHotKey: previous)
        fixture.coordinator.start()

        fixture.hotKey.errorToThrow = .alreadyRegistered
        let saved = fixture.coordinator.updateGlobalHotKey(conflicting)

        XCTAssertFalse(saved)
        XCTAssertEqual(fixture.coordinator.hotKeyError, .alreadyRegistered)
        XCTAssertNotNil(fixture.coordinator.hotKeyError?.errorDescription)
        XCTAssertEqual(fixture.preferences.globalANCHotKey, previous)
    }

    func testGlobalHotKeyIgnoredWhileRecording() async {
        let shortcut = MacroKeyShortcut(keyCode: UInt16(kVK_ANSI_A), modifiers: [.command, .shift])
        let fixture = makeFixture(callRuleEnabled: false, storedHotKey: shortcut)
        fixture.coordinator.start()
        fixture.link.onState?(ancState(0x01))
        await flush()

        fixture.coordinator.isRecordingHotKey = true
        fixture.hotKey.simulateTrigger()

        XCTAssertTrue(fixture.link.sent.isEmpty)
    }

    // MARK: - Inércia e ciclo de vida

    func testStartsInertWhenNoHotKeyAndCallRuleDisabled() {
        let fixture = makeFixture(callRuleEnabled: false, storedHotKey: nil)
        fixture.coordinator.start()

        XCTAssertTrue(fixture.hotKey.registered.isEmpty)
        XCTAssertEqual(fixture.callMonitor.startCount, 0)
    }

    func testTogglingCallRuleStartsAndStopsAudioMonitor() {
        let fixture = makeFixture(callRuleEnabled: false)
        fixture.coordinator.start()
        XCTAssertEqual(fixture.callMonitor.startCount, 0)

        fixture.coordinator.setCallRuleEnabled(true)
        XCTAssertEqual(fixture.callMonitor.startCount, 1)

        fixture.coordinator.setCallRuleEnabled(false)
        XCTAssertEqual(fixture.callMonitor.stopCount, 1)
    }

    // MARK: - Chamada e Foco fim a fim

    func testCallActivityAppliesConfiguredSceneAndRestoresPrevious() async {
        let fixture = makeFixture(callRuleEnabled: true, callRuleScene: .transparency)
        fixture.link.autoEchoANC = true
        fixture.coordinator.start()
        fixture.link.onState?(ancState(0x01)) // ANC
        await flush()

        fixture.callMonitor.simulateCall(true)
        await flush(.milliseconds(80))
        XCTAssertEqual(fixture.model.ancChoice, .transparency)
        XCTAssertTrue(fixture.coordinator.isCallActive)

        fixture.callMonitor.simulateCall(false)
        await flush(.milliseconds(80))
        XCTAssertEqual(fixture.model.ancChoice, .anc)
        XCTAssertFalse(fixture.coordinator.isCallActive)
    }

    func testFocusFilterAppliesAndRestoresAndTracksActiveState() async {
        let fixture = makeFixture(callRuleEnabled: false)
        fixture.link.autoEchoANC = true
        fixture.coordinator.start()
        fixture.link.onState?(ancState(0x02)) // Normal
        await flush()

        await fixture.coordinator.handleFocusFilter(.anc)
        XCTAssertEqual(fixture.coordinator.activeFocusScene, .anc)
        XCTAssertEqual(fixture.model.ancChoice, .anc)

        await fixture.coordinator.handleFocusFilter(nil)
        XCTAssertNil(fixture.coordinator.activeFocusScene)
        XCTAssertEqual(fixture.model.ancChoice, .normal)
    }

    func testOverlapFocusAndCallAppliesLatestAndRestoresOriginalEndToEnd() async {
        let fixture = makeFixture(callRuleEnabled: true, callRuleScene: .transparency)
        fixture.link.autoEchoANC = true
        fixture.coordinator.start()
        fixture.link.onState?(ancState(0x02)) // Normal
        await flush()

        await fixture.coordinator.handleFocusFilter(.anc)
        XCTAssertEqual(fixture.model.ancChoice, .anc)

        fixture.callMonitor.simulateCall(true)
        await flush(.milliseconds(80))
        XCTAssertEqual(fixture.model.ancChoice, .transparency)

        fixture.callMonitor.simulateCall(false)
        await flush(.milliseconds(80))
        XCTAssertEqual(fixture.model.ancChoice, .anc)

        await fixture.coordinator.handleFocusFilter(nil)
        XCTAssertEqual(fixture.model.ancChoice, .normal)
    }

    func testCarbonModifierConversionMapsAllModifiers() {
        let all: Set<MacroKeyModifier> = [.command, .shift, .option, .control]
        let flags = CarbonGlobalHotKeyRegistrar.carbonModifiers(from: all)
        XCTAssertEqual(flags, UInt32(cmdKey | shiftKey | optionKey | controlKey))
        XCTAssertEqual(CarbonGlobalHotKeyRegistrar.carbonModifiers(from: []), 0)
    }

    func testFocusFilterIntentDisplayRepresentationReflectsMode() {
        let active = QCYFocusFilterIntent(mode: .anc)
        XCTAssertEqual(active.mode?.choice, .anc)
        XCTAssertEqual(
            active.displayRepresentation.subtitle,
            QCYNoiseModeAppEnum.caseDisplayRepresentations[.anc]?.title
        )

        let inactive = QCYFocusFilterIntent(mode: nil)
        XCTAssertNil(inactive.mode)
        XCTAssertEqual(inactive.displayRepresentation.subtitle, "qcy.intent.focusFilter.inactive")
    }
}
