import Foundation

/// Liga `GestureSource` -> `MacroStore` -> `MacroRunner`.
/// Permanece inerte enquanto não houver macros salvas (sem reclamar Now Playing nem pedir Acessibilidade).
@MainActor
final class MacroCoordinator {
    let store: MacroStore
    let runner: MacroRunner
    let gestureSource: any GestureSource
    var onExecutionCompleted: ((UUID, MacroRunOutcome) -> Void)?

    private(set) var isRunning = false
    private var activeTasks: [UUID: Task<Void, Never>] = [:]

    init(
        store: MacroStore,
        runner: MacroRunner = MacroRunner(),
        gestureSource: any GestureSource = CompositeGestureSource()
    ) {
        self.store = store
        self.runner = runner
        self.gestureSource = gestureSource
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true

        store.onChange = { [weak self] _ in
            self?.syncActiveCommands()
        }
        gestureSource.onCommand = { [weak self] command in
            self?.handle(command) ?? false
        }
        store.load()
    }

    func stop() {
        isRunning = false
        store.onChange = nil
        gestureSource.onCommand = nil
        gestureSource.stop()
        for task in activeTasks.values {
            task.cancel()
        }
        activeTasks.removeAll()
    }

    @discardableResult
    func handle(_ command: MediaCommand) -> Bool {
        guard isRunning, let macro = store.macro(for: command) else {
            return false
        }
        let executionToken = UUID()
        let runner = self.runner
        activeTasks[executionToken] = Task { @MainActor [weak self] in
            let result = await runner.run(macro)
            self?.activeTasks.removeValue(forKey: executionToken)
            self?.onExecutionCompleted?(macro.id, result)
        }
        return true
    }

    private func syncActiveCommands() {
        guard isRunning else { return }
        gestureSource.updateActiveCommands(store.activeTriggers)
    }
}
