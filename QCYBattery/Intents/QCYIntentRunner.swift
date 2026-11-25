import Foundation
import QCYKit

/// Erros legíveis expostos ao app Atalhos quando uma intent não consegue ler ou gravar no fone.
enum QCYIntentError: Error, LocalizedError, CustomLocalizedStringResourceConvertible, Equatable, Sendable {
    case notConnected
    case writeFailed
    case readOnly

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notConnected: "qcy.intent.error.notConnected"
        case .writeFailed: "qcy.intent.error.writeFailed"
        case .readOnly: "qcy.intent.error.readOnly"
        }
    }

    var errorDescription: String? {
        String(localized: localizedStringResource)
    }
}

/// Lógica compartilhada entre as App Intents e o `QCYViewModel`: espera conexão, aplica a escrita otimista e só
/// confirma depois do eco do fone (ou falha com erro legível).
@MainActor
struct QCYIntentRunner {
    let model: QCYViewModel
    let connectionTimeout: Duration
    let writeTimeout: Duration
    let pollInterval: Duration

    init(
        model: QCYViewModel,
        connectionTimeout: Duration = .seconds(5),
        writeTimeout: Duration = .seconds(4),
        pollInterval: Duration = .milliseconds(50)
    ) {
        self.model = model
        self.connectionTimeout = connectionTimeout
        self.writeTimeout = writeTimeout
        self.pollInterval = pollInterval
    }

    func setNoiseMode(_ choice: QCYANCChoice) async throws {
        try await performWrite(
            alreadyApplied: { model.ancChoice == choice },
            trigger: { model.select(choice) }
        )
    }

    func setSoundEffect(_ effect: QCYSoundEffect) async throws {
        try await performWrite(
            alreadyApplied: { model.soundEffect == effect },
            trigger: { model.choose(effect: effect) }
        )
    }

    func readBattery() async throws -> QCYBatteryStatus {
        try await waitForConnection()
        return QCYBatteryStatus(
            summary: model.menuBarText,
            leftPercent: model.state.left?.percent,
            rightPercent: model.state.right?.percent
        )
    }

    // MARK: - Espera e confirmação

    private func waitForConnection() async throws {
        if model.phase == .connected { return }
        let deadline = ContinuousClock.now + connectionTimeout
        while model.phase != .connected {
            let remaining = deadline - ContinuousClock.now
            if remaining <= .zero {
                throw QCYIntentError.notConnected
            }
            try await Task.sleep(for: min(pollInterval, remaining))
        }
    }

    private func waitForIdlePending() async throws {
        guard model.pending != nil else { return }
        let deadline = ContinuousClock.now + writeTimeout
        while model.pending != nil {
            let remaining = deadline - ContinuousClock.now
            if remaining <= .zero {
                throw QCYIntentError.writeFailed
            }
            try await Task.sleep(for: min(pollInterval, remaining))
        }
        guard model.phase == .connected else {
            throw QCYIntentError.notConnected
        }
    }

    private func performWrite(
        alreadyApplied: () -> Bool,
        trigger: () -> Void
    ) async throws {
        if model.isReadOnly {
            throw QCYIntentError.readOnly
        }
        try await waitForConnection()
        try await waitForIdlePending()
        if alreadyApplied() {
            return
        }

        trigger()
        guard model.pending != nil else {
            throw model.phase == .connected ? QCYIntentError.writeFailed : QCYIntentError.notConnected
        }

        let deadline = ContinuousClock.now + writeTimeout
        while model.pending != nil {
            let remaining = deadline - ContinuousClock.now
            if remaining <= .zero {
                throw QCYIntentError.writeFailed
            }
            try await Task.sleep(for: min(pollInterval, remaining))
        }

        guard model.phase == .connected else {
            throw QCYIntentError.notConnected
        }
        guard !model.writeFailed, alreadyApplied() else {
            throw QCYIntentError.writeFailed
        }
    }
}
