import Foundation

extension QCYViewModel {
    /// O scan sem duplicatas não reporta de novo um fone já visto e o link GATT aberto pelo macOS não anuncia:
    /// desconectado, reinicia a busca sozinho em vez de esperar o "Procurar de novo".
    func startRescanLoop() {
        rescanTask?.cancel()
        rescanTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.rescanInterval ?? .seconds(10))
                guard let self, !Task.isCancelled else { return }
                if phase == .disconnected, !isLinked {
                    link.stop()
                    link.start()
                }
            }
        }
    }
}
