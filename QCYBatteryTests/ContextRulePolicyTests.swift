import XCTest
@testable import QCYBattery

final class ContextRulePolicyTests: XCTestCase {
    func testEnterAppliesTargetAndSavesPreviousAndExitRestores() {
        var policy = ContextRulePolicy()
        let settings = ContextRuleSettings(callEnabled: true, callScene: .transparency)

        let onEnter = policy.enterCall(settings: settings, currentScene: .anc)
        XCTAssertEqual(onEnter, .transparency)
        XCTAssertEqual(policy.savedScene, .anc)
        XCTAssertTrue(policy.isActive(.call))

        let onExit = policy.exitCall(currentScene: .transparency)
        XCTAssertEqual(onExit, .anc)
        XCTAssertNil(policy.savedScene)
        XCTAssertFalse(policy.isActive(.call))
    }

    func testManualChangeDuringContextIsNotOverwrittenOnExit() {
        var policy = ContextRulePolicy()
        let settings = ContextRuleSettings(callEnabled: true, callScene: .transparency)

        XCTAssertEqual(policy.enterCall(settings: settings, currentScene: .anc), .transparency)

        // Usuário trocou manualmente para Normal durante a chamada.
        let onExit = policy.exitCall(currentScene: .normal)
        XCTAssertNil(onExit)
        XCTAssertNil(policy.savedScene)
        XCTAssertTrue(policy.activeContexts.isEmpty)
    }

    func testDisabledCallRuleDoesNothing() {
        var policy = ContextRulePolicy()
        let disabled = ContextRuleSettings(callEnabled: false, callScene: .transparency)

        XCTAssertNil(policy.enterCall(settings: disabled, currentScene: .anc))
        XCTAssertNil(policy.savedScene)
        XCTAssertTrue(policy.activeContexts.isEmpty)

        XCTAssertNil(policy.exitCall(currentScene: .anc))
    }

    func testEnterWhenAlreadyOnTargetSavesPreviousWithoutWriting() {
        var policy = ContextRulePolicy()
        let settings = ContextRuleSettings(callEnabled: true, callScene: .transparency)

        XCTAssertNil(policy.enterCall(settings: settings, currentScene: .transparency))
        XCTAssertEqual(policy.savedScene, .transparency)
        XCTAssertTrue(policy.isActive(.call))

        XCTAssertNil(policy.exitCall(currentScene: .transparency))
        XCTAssertNil(policy.savedScene)
    }

    func testOverlapFocusThenCallLatestWinsAndRestoresOriginalScene() {
        var policy = ContextRulePolicy()
        let settings = ContextRuleSettings(callEnabled: true, callScene: .transparency)

        // Cena inicial antes do primeiro contexto: Normal.
        XCTAssertEqual(policy.enterFocus(target: .anc, currentScene: .normal), .anc)
        XCTAssertEqual(policy.savedScene, .normal)

        // Chamada entra sobre o Foco: última a entrar vence (Transparência), mas a cena salva continua Normal.
        XCTAssertEqual(policy.enterCall(settings: settings, currentScene: .anc), .transparency)
        XCTAssertEqual(policy.savedScene, .normal)
        XCTAssertEqual(policy.activeContexts, [.focus, .call])

        // Chamada sai primeiro: volta para a cena do Foco ainda ativo (ANC).
        XCTAssertEqual(policy.exitCall(currentScene: .transparency), .anc)
        XCTAssertEqual(policy.savedScene, .normal)
        XCTAssertEqual(policy.activeContexts, [.focus])

        // Foco sai depois: restaura a cena anterior ao primeiro contexto (Normal).
        XCTAssertEqual(policy.exitFocus(currentScene: .anc), .normal)
        XCTAssertNil(policy.savedScene)
        XCTAssertTrue(policy.activeContexts.isEmpty)
    }

    func testOverlapFirstContextExitsBeforeSecondRestoresOriginalWhenSecondExits() {
        var policy = ContextRulePolicy()
        let settings = ContextRuleSettings(callEnabled: true, callScene: .transparency)

        XCTAssertEqual(policy.enterFocus(target: .anc, currentScene: .normal), .anc)
        XCTAssertEqual(policy.enterCall(settings: settings, currentScene: .anc), .transparency)

        // Foco sai enquanto chamada ainda está no topo: mantém a cena da chamada.
        XCTAssertNil(policy.exitFocus(currentScene: .transparency))
        XCTAssertEqual(policy.savedScene, .normal)
        XCTAssertEqual(policy.activeContexts, [.call])

        // Quando a chamada sai, restaura a cena anterior ao primeiro contexto (Normal).
        XCTAssertEqual(policy.exitCall(currentScene: .transparency), .normal)
        XCTAssertNil(policy.savedScene)
        XCTAssertTrue(policy.activeContexts.isEmpty)
    }

    func testOverlapCallThenFocusLatestWinsAndRestoresOriginal() {
        var policy = ContextRulePolicy()
        let settings = ContextRuleSettings(callEnabled: true, callScene: .transparency)

        XCTAssertEqual(policy.enterCall(settings: settings, currentScene: .normal), .transparency)
        XCTAssertEqual(policy.enterFocus(target: .anc, currentScene: .transparency), .anc)
        XCTAssertEqual(policy.savedScene, .normal)

        XCTAssertEqual(policy.exitFocus(currentScene: .anc), .transparency)
        XCTAssertEqual(policy.exitCall(currentScene: .transparency), .normal)
    }

    func testManualOverrideDuringOverlapPreventsUnexpectedRestore() {
        var policy = ContextRulePolicy()
        let settings = ContextRuleSettings(callEnabled: true, callScene: .transparency)

        XCTAssertEqual(policy.enterFocus(target: .anc, currentScene: .normal), .anc)
        XCTAssertEqual(policy.enterCall(settings: settings, currentScene: .anc), .transparency)

        // Usuário trocou manualmente para Normal durante a sobreposição.
        XCTAssertNil(policy.exitCall(currentScene: .normal))
        XCTAssertNil(policy.exitFocus(currentScene: .normal))
        XCTAssertNil(policy.savedScene)
    }

    func testReenteringFocusWithDifferentScenePreservesOriginalSavedScene() {
        var policy = ContextRulePolicy()

        XCTAssertEqual(policy.enterFocus(target: .anc, currentScene: .transparency), .anc)
        XCTAssertEqual(policy.enterFocus(target: .normal, currentScene: .anc), .normal)
        XCTAssertEqual(policy.savedScene, .transparency)

        XCTAssertEqual(policy.exitFocus(currentScene: .normal), .transparency)
        XCTAssertNil(policy.savedScene)
    }
}
