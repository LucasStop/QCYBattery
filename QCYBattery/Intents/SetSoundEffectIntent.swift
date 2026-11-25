import AppIntents
import Foundation
import QCYKit

/// Presets medidos de efeito de som expostos no app Atalhos, mapeados para `QCYSoundEffect`.
enum QCYSoundEffectAppEnum: String, AppEnum {
    case spatial = "spatial"
    case standard = "default"
    case pop = "pop"
    case heavyBass = "heavyBass"

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "qcy.intent.soundEffect.type")

    static let caseDisplayRepresentations: [QCYSoundEffectAppEnum: DisplayRepresentation] = [
        .spatial: DisplayRepresentation(
            title: "qcy.sound.effect.spatial",
            image: .init(systemName: "dot.radiowaves.left.and.right")
        ),
        .standard: DisplayRepresentation(
            title: "qcy.sound.effect.default",
            image: .init(systemName: "waveform")
        ),
        .pop: DisplayRepresentation(
            title: "qcy.sound.effect.pop",
            image: .init(systemName: "chart.bar.fill")
        ),
        .heavyBass: DisplayRepresentation(
            title: "qcy.sound.effect.heavyBass",
            image: .init(systemName: "record.circle")
        )
    ]

    var soundEffect: QCYSoundEffect {
        switch self {
        case .spatial: .spatial
        case .standard: .default
        case .pop: .pop
        case .heavyBass: .heavyBass
        }
    }
}

/// App Intent para definir um dos 4 efeitos de som medidos no fone conectado.
struct SetSoundEffectIntent: AppIntent {
    static let title: LocalizedStringResource = "qcy.intent.setSoundEffect.title"
    static let description = IntentDescription("qcy.intent.setSoundEffect.description")

    @Parameter(title: "qcy.intent.soundEffect.parameter")
    var effect: QCYSoundEffectAppEnum

    @Dependency
    private var model: QCYViewModel

    static var parameterSummary: some ParameterSummary {
        Summary("Definir efeito de som como \(\.$effect)")
    }

    init() {}

    init(effect: QCYSoundEffectAppEnum) {
        self.effect = effect
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        try await QCYIntentRunner(model: model).setSoundEffect(effect.soundEffect)
        let title = QCYSoundEffectAppEnum.caseDisplayRepresentations[effect]?.title ?? "qcy.sound.effect.default"
        return .result(dialog: IntentDialog(title))
    }
}
