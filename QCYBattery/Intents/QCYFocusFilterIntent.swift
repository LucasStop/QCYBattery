import AppIntents
import Foundation

/// Filtro de Foco do macOS (US-10): aplica a cena de ANC configurada em Ajustes do Sistema > Foco > Filtros de Foco >
/// QCYBattery quando o Foco ativa, e restaura a cena anterior quando o Foco desativa (`mode == nil`).
struct QCYFocusFilterIntent: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "qcy.intent.focusFilter.title"
    static let description = IntentDescription("qcy.intent.focusFilter.description")

    @Parameter(title: "qcy.intent.noiseMode.parameter")
    var mode: QCYNoiseModeAppEnum?

    @Dependency
    private var coordinator: ContextRuleCoordinator

    init() {}

    init(mode: QCYNoiseModeAppEnum?) {
        self.mode = mode
    }

    var displayRepresentation: DisplayRepresentation {
        if let mode, let modeTitle = QCYNoiseModeAppEnum.caseDisplayRepresentations[mode]?.title {
            return DisplayRepresentation(
                title: "qcy.intent.focusFilter.title",
                subtitle: modeTitle
            )
        }
        return DisplayRepresentation(
            title: "qcy.intent.focusFilter.title",
            subtitle: "qcy.intent.focusFilter.inactive"
        )
    }

    func perform() async throws -> some IntentResult {
        await coordinator.handleFocusFilter(mode?.choice)
        return .result()
    }
}
