import AppIntents
import Foundation

/// Opções de modo de ruído expostas no app Atalhos, mapeadas para `QCYANCChoice`.
enum QCYNoiseModeAppEnum: String, AppEnum {
    case anc
    case normal
    case transparency

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "qcy.intent.noiseMode.type")

    static let caseDisplayRepresentations: [QCYNoiseModeAppEnum: DisplayRepresentation] = [
        .anc: DisplayRepresentation(
            title: "qcy.anc.anc",
            image: .init(systemName: "waveform.slash")
        ),
        .normal: DisplayRepresentation(
            title: "qcy.anc.normal",
            image: .init(systemName: "headphones")
        ),
        .transparency: DisplayRepresentation(
            title: "qcy.anc.transparency",
            image: .init(systemName: "ear")
        )
    ]

    var choice: QCYANCChoice {
        switch self {
        case .anc: .anc
        case .normal: .normal
        case .transparency: .transparency
        }
    }
}

/// App Intent para definir o modo de ruído (ANC, Normal ou Transparência) no fone conectado.
struct SetNoiseModeIntent: AppIntent {
    static let title: LocalizedStringResource = "qcy.intent.setNoiseMode.title"
    static let description = IntentDescription("qcy.intent.setNoiseMode.description")

    @Parameter(title: "qcy.intent.noiseMode.parameter")
    var mode: QCYNoiseModeAppEnum

    @Dependency
    private var model: QCYViewModel

    static var parameterSummary: some ParameterSummary {
        Summary("Definir modo de ruído como \(\.$mode)")
    }

    init() {}

    init(mode: QCYNoiseModeAppEnum) {
        self.mode = mode
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await QCYIntentRunner(model: model).setNoiseMode(mode.choice)
        let title = QCYNoiseModeAppEnum.caseDisplayRepresentations[mode]?.title ?? "qcy.anc.anc"
        return .result(dialog: IntentDialog(title))
    }
}
