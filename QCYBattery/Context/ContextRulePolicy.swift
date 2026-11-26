import Foundation

/// Origem de uma regra automática de cena de ANC por contexto (US-10).
enum ANCContextKind: String, Equatable, Hashable, Sendable {
    case call
    case focus
}

/// Preferências das regras de ANC por contexto lidas pelo `ContextRulePolicy`.
struct ContextRuleSettings: Equatable, Sendable {
    var callEnabled: Bool
    var callScene: QCYANCChoice

    static let `default` = ContextRuleSettings(callEnabled: true, callScene: .transparency)
}

/// Política pura de entrada, sobreposição e restauração de cenas de ANC por contexto (US-10).
///
/// Regras:
/// - Ao entrar no primeiro contexto ativo, guarda a cena anterior em memória e aplica a cena da regra.
/// - Em sobreposição (chamada + Foco), o último contexto a entrar vence e a cena anterior preservada continua sendo
///   a cena anterior ao primeiro contexto.
/// - Ao sair de um contexto: se ainda há outro ativo, aplica a cena do último remanescente; se nenhum restar,
///   restaura a cena anterior salva — mas apenas se a cena atual ainda for a que a regra aplicou, evitando
///   sobrescrever uma troca manual do usuário.
/// - Regra de chamada desligada em `ContextRuleSettings` não entra nem altera a cena.
struct ContextRulePolicy: Sendable {
    private struct ActiveEntry: Equatable, Sendable {
        let kind: ANCContextKind
        let target: QCYANCChoice
    }

    private var activeStack: [ActiveEntry] = []
    private(set) var savedScene: QCYANCChoice?
    private(set) var lastAppliedScene: QCYANCChoice?

    var activeContexts: [ANCContextKind] {
        activeStack.map(\.kind)
    }

    func isActive(_ kind: ANCContextKind) -> Bool {
        activeStack.contains { $0.kind == kind }
    }

    /// Registra entrada (ou atualização de cena) em chamada em andamento respeitando `settings`.
    mutating func enterCall(
        settings: ContextRuleSettings,
        currentScene: QCYANCChoice?
    ) -> QCYANCChoice? {
        guard settings.callEnabled else { return nil }
        return enter(.call, target: settings.callScene, currentScene: currentScene)
    }

    /// Registra saída de chamada em andamento.
    mutating func exitCall(currentScene: QCYANCChoice?) -> QCYANCChoice? {
        exit(.call, currentScene: currentScene)
    }

    /// Registra entrada em um modo de Foco com filtro do QCYBattery.
    mutating func enterFocus(
        target: QCYANCChoice,
        currentScene: QCYANCChoice?
    ) -> QCYANCChoice? {
        enter(.focus, target: target, currentScene: currentScene)
    }

    /// Registra saída do modo de Foco (filtro desativado).
    mutating func exitFocus(currentScene: QCYANCChoice?) -> QCYANCChoice? {
        exit(.focus, currentScene: currentScene)
    }

    /// Entra em um contexto arbitrário, preservando a cena anterior ao primeiro contexto da pilha.
    mutating func enter(
        _ kind: ANCContextKind,
        target: QCYANCChoice,
        currentScene: QCYANCChoice?
    ) -> QCYANCChoice? {
        if activeStack.isEmpty {
            savedScene = currentScene
        }
        activeStack.removeAll { $0.kind == kind }
        activeStack.append(ActiveEntry(kind: kind, target: target))
        lastAppliedScene = target
        return currentScene == target ? nil : target
    }

    /// Sai de um contexto. Se o usuário mudou a cena manualmente desde a última aplicação, não sobrescreve.
    mutating func exit(
        _ kind: ANCContextKind,
        currentScene: QCYANCChoice?
    ) -> QCYANCChoice? {
        guard let index = activeStack.firstIndex(where: { $0.kind == kind }) else {
            return nil
        }

        let wasTop = index == activeStack.count - 1
        activeStack.remove(at: index)

        if activeStack.isEmpty {
            let restoreTarget = savedScene
            let expectedScene = lastAppliedScene
            savedScene = nil
            lastAppliedScene = nil

            guard let restoreTarget,
                  let expectedScene,
                  currentScene == expectedScene else {
                return nil
            }
            return currentScene == restoreTarget ? nil : restoreTarget
        }

        // Um contexto que estava por baixo saiu: o contexto no topo continua valendo.
        guard wasTop else { return nil }

        // O contexto do topo saiu; só devolve a cena do contexto remanescente se não houve troca manual.
        guard let expectedScene = lastAppliedScene, currentScene == expectedScene else {
            lastAppliedScene = nil
            return nil
        }

        let nextTarget = activeStack[activeStack.count - 1].target
        lastAppliedScene = nextTarget
        return currentScene == nextTarget ? nil : nextTarget
    }
}
