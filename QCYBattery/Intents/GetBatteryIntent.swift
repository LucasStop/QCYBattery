import AppIntents
import Foundation

/// Resultado estruturado da consulta de bateria: resumo textual (`L n% · R n%`) e porcentagens por lado.
struct QCYBatteryStatus: TransientAppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "qcy.intent.battery.entity")

    @Property(title: "qcy.intent.battery.summary")
    var summary: String

    @Property(title: "qcy.side.left")
    var leftPercent: Int?

    @Property(title: "qcy.side.right")
    var rightPercent: Int?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(summary)",
            image: .init(systemName: "battery.100")
        )
    }

    init() {
        summary = "L — · R —"
    }

    init(summary: String, leftPercent: Int?, rightPercent: Int?) {
        self.summary = summary
        self.leftPercent = leftPercent
        self.rightPercent = rightPercent
    }
}

/// App Intent para consultar a bateria atual por lado do fone conectado.
struct GetBatteryIntent: AppIntent {
    static let title: LocalizedStringResource = "qcy.intent.getBattery.title"
    static let description = IntentDescription(
        "qcy.intent.getBattery.description",
        resultValueName: "qcy.intent.battery.entity"
    )

    @Dependency
    private var model: QCYViewModel

    func perform() async throws -> some IntentResult & ReturnsValue<QCYBatteryStatus> & ProvidesDialog {
        let status = try await QCYIntentRunner(model: model).readBattery()
        return .result(value: status, dialog: IntentDialog("\(status.summary)"))
    }
}
