import Foundation
import Observation
import QCYKit

/// Canal com o fone, atrás de protocolo para os testes trocarem o CoreBluetooth por um fake.
protocol QCYLink: AnyObject, Sendable {
    var onState: (@Sendable (QCYState) -> Void)? { get set }
    var onAdvertisement: (@Sendable (QCYAdvertisement) -> Void)? { get set }
    var onReady: (@Sendable () -> Void)? { get set }
    var onDisconnect: (@Sendable () -> Void)? { get set }
    func start()
    func stop()
    func refresh()
    func refreshKeyMap()
    func send(_ packet: QCYPacket)
    func setKeyFunction(_ function: QCYKeyFunction, for gesture: QCYGesture)
}

extension QCYClient: QCYLink {}

/// Cena de ANC que a tela oferece. O `0x17` é a única via de escrita (o `0x0C` não responde no MeloBuds Pro);
/// os bytes são os medidos em `docs/QCY.md` §5.
enum QCYANCChoice: CaseIterable, Equatable, Sendable {
    case anc, normal, transparency

    var packet: QCYPacket {
        switch self {
        case .anc: .ancSetting(mode: 0x01, subScene: 0x02, noiseValue: 0x03)
        case .normal: .ancSetting(mode: 0x02, subScene: 0x00, noiseValue: 0x00)
        case .transparency: .ancSetting(mode: 0x03, subScene: 0x02, noiseValue: 0x00)
        }
    }

    init?(scene: QCYANScene) {
        switch scene.mode {
        case 0x01: self = .anc
        case 0x02: self = .normal
        case 0x03: self = .transparency
        default: return nil
        }
    }
}

/// Escrita enviada e ainda sem eco do fone.
enum QCYPending: Equatable, Sendable {
    case anc(QCYANCChoice)
    case ldac(Bool)
    case game(Bool)
    case soundEffect(QCYSoundEffect)
    case vocalBoost(Bool)
    case balance(UInt8)
    case key(QCYGesture, QCYKeyFunction)
    case powerOff(QCYPowerOff)
    case toneVolume(QCYToneVolume)
    case wearDetection(Bool)
}

/// Estado da janela do fone (T12). O controle só muda depois do eco do fone; sem eco no prazo, ou com o link
/// caído, volta ao valor lido.
@MainActor
@Observable
final class QCYViewModel {
    enum Phase: Equatable { case loading, connected, disconnected }

    private(set) var phase: Phase = .loading
    private(set) var state = QCYState()
    private(set) var address: String?
    private(set) var pending: QCYPending?
    private(set) var writeFailed = false
    let isReadOnly: Bool
    let macroStore: MacroStore

    @ObservationIgnored private let link: any QCYLink
    @ObservationIgnored private let notifier: any BatteryNotifying
    @ObservationIgnored private let alertSettings: @MainActor () -> BatteryAlertSettings
    @ObservationIgnored private let writeTimeout: Duration
    @ObservationIgnored private let settleTimeout: Duration
    @ObservationIgnored private let pollInterval: Duration
    @ObservationIgnored private var alertPolicy = BatteryAlertPolicy()
    @ObservationIgnored private var isLinked = false
    @ObservationIgnored private var lastTransparencyLevel: UInt8 = 3
    @ObservationIgnored private var writeTask: Task<Void, Never>?
    @ObservationIgnored private var readbackTask: Task<Void, Never>?
    @ObservationIgnored private var settleTask: Task<Void, Never>?
    @ObservationIgnored private var pollTask: Task<Void, Never>?

    init(
        link: any QCYLink,
        isReadOnly: Bool = false,
        writeTimeout: Duration = .seconds(3),
        settleTimeout: Duration = .seconds(3),
        pollInterval: Duration = .seconds(30),
        notifier: any BatteryNotifying = NoOpBatteryNotifier(),
        alertSettings: @escaping @MainActor () -> BatteryAlertSettings = { .allEnabled },
        macroStore: MacroStore = .inMemory()
    ) {
        self.link = link
        self.notifier = notifier
        self.alertSettings = alertSettings
        self.isReadOnly = isReadOnly
        self.macroStore = macroStore
        self.writeTimeout = writeTimeout
        self.settleTimeout = settleTimeout
        self.pollInterval = pollInterval
        link.onState = { [weak self] state in Task { @MainActor in self?.receive(state) } }
        link.onAdvertisement = { [weak self] advertisement in Task { @MainActor in self?.receive(advertisement) } }
        link.onReady = { [weak self] in Task { @MainActor in self?.linkReady() } }
        link.onDisconnect = { [weak self] in Task { @MainActor in self?.linkLost() } }
    }

    // MARK: - Ciclo de vida

    func start() {
        link.start()
        settle(after: settleTimeout) { [self] in
            if phase == .loading, !isLinked { phase = .disconnected }
        }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(30))
                guard let self, !Task.isCancelled else { return }
                if phase == .connected, pending == nil {
                    link.refresh()
                    link.refreshKeyMap()
                }
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        writeTask?.cancel()
        readbackTask?.cancel()
        settleTask?.cancel()
        link.stop()
    }

    /// "Procurar de novo" da tela sem conexão.
    func reconnect() {
        link.stop()
        phase = .loading
        link.start()
        settle(after: settleTimeout) { [self] in
            if phase == .loading, !isLinked { phase = .disconnected }
        }
    }

    /// "Tentar de novo" do erro de escrita: limpa o aviso e relê o retrato.
    func retryAfterFailure() {
        writeFailed = false
        link.refresh()
        link.refreshKeyMap()
    }

    // MARK: - Escrita

    func select(_ choice: QCYANCChoice) {
        guard !areControlsDisabled, choice != ancChoice else { return }
        begin(.anc(choice), choice.packet)
    }

    func setLDAC(_ enabled: Bool) {
        guard !areControlsDisabled, enabled != isLDACOn else { return }
        begin(.ldac(enabled), .setLDAC(enabled))
    }

    func setGame(_ enabled: Bool) {
        guard !areControlsDisabled, enabled != isGameOn else { return }
        begin(.game(enabled), .setLowLatency(enabled))
    }

    func choose(effect: QCYSoundEffect) {
        guard !areControlsDisabled, effect != soundEffect,
              let packet = QCYPacket.setSoundEffect(effect) else { return }
        begin(.soundEffect(effect), packet)
    }

    func setVocalBoost(_ enabled: Bool) {
        guard !areControlsDisabled, isVocalBoostAvailable, enabled != isVocalBoostOn else { return }
        let packet: QCYPacket = enabled ? .transparencyVocal() : .transparency(level: lastTransparencyLevel)
        begin(.vocalBoost(enabled), packet)
    }

    func setBalance(_ value: UInt8) {
        let clamped = min(value, 100)
        guard !areControlsDisabled, clamped != balance else { return }
        begin(.balance(clamped), .setBalance(clamped))
    }

    func choose(function: QCYKeyFunction, for gesture: QCYGesture) {
        guard !areControlsDisabled, keyMap[gesture] != function else { return }
        begin(.key(gesture, function)) { link.setKeyFunction(function, for: gesture) }
    }

    func choose(powerOff target: QCYPowerOff) {
        guard !areControlsDisabled, target != powerOff else { return }
        begin(.powerOff(target), .setPowerOff(target))
    }

    func choose(toneVolume target: QCYToneVolume) {
        guard !areControlsDisabled, target != toneVolume else { return }
        begin(.toneVolume(target), .setToneVolume(target))
    }

    func setWearDetection(_ enabled: Bool) {
        guard !areControlsDisabled, let current = state.wearDetection, enabled != isWearDetectionOn else { return }
        let updated = QCYWearDetection(
            isEnabled: enabled,
            musicControl: current.musicControl,
            isANCSwitchEnabled: current.isANCSwitchEnabled
        )
        begin(.wearDetection(enabled), .setWearDetection(updated))
    }

    private func begin(_ write: QCYPending, _ packet: QCYPacket) {
        begin(write) { link.send(packet) }
    }

    private func begin(_ write: QCYPending, perform action: () -> Void) {
        pending = write
        writeFailed = false
        action()
        writeTask?.cancel()
        readbackTask?.cancel()
        // Balanço, efeitos, desligamento, volume e detecção de uso não geram notificação: o fone só
        // confirma o valor novo quando lido de volta.
        readbackTask = Task { [weak self] in
            for delay in [Duration.milliseconds(400), .milliseconds(500)] {
                try? await Task.sleep(for: delay)
                guard let self, !Task.isCancelled else { return }
                link.refresh()
            }
        }
        writeTask = Task { [weak self] in
            try? await Task.sleep(for: self?.writeTimeout ?? .seconds(3))
            guard let self, !Task.isCancelled else { return }
            pending = nil
            writeFailed = true
        }
    }

    // MARK: - Eventos do link

    private func receive(_ newState: QCYState) {
        state = newState
        if let scene = newState.ancScene, scene.mode == 0x03, scene.subScene == 0x01,
           (1...6).contains(scene.noiseValue) {
            lastTransparencyLevel = scene.noiseValue
        }
        phase = .connected
        settleTask?.cancel()
        for alert in alertPolicy.evaluate(state: newState, settings: alertSettings()) {
            notifier.notify(alert)
        }
        guard let write = pending else { return }
        if isConfirmed(write) {
            pending = nil
            writeTask?.cancel()
            readbackTask?.cancel()
        }
    }

    private func isConfirmed(_ write: QCYPending) -> Bool {
        switch write {
        case .anc(let target): ancChoice == target
        case .ldac(let value): state.isLDACEnabled == value
        case .game(let value): state.isLowLatencyEnabled == value
        case .soundEffect(let target): state.soundEffect == target
        case .vocalBoost(let enabled):
            state.ancScene?.mode == 0x03 && state.ancScene?.subScene == (enabled ? 0x02 : 0x01)
        default: isSettingConfirmed(write)
        }
    }

    private func isSettingConfirmed(_ write: QCYPending) -> Bool {
        switch write {
        case .balance(let target): state.balance == target
        case .key(let gesture, let function): state.keyMap[gesture] == function
        case .powerOff(let target): state.powerOff == target
        case .toneVolume(let target): state.toneVolume == target
        case .wearDetection(let enabled): state.wearDetection?.isEnabled == enabled
        default: false
        }
    }

    private func receive(_ advertisement: QCYAdvertisement) {
        if let mac = advertisement.controlMAC { address = mac }
    }

    /// Características descobertas: o retrato chega logo em seguida. Se não chegar, mostra "sem leitura" em vez
    /// de ficar carregando para sempre.
    private func linkReady() {
        isLinked = true
        settle(after: settleTimeout) { [self] in
            if phase == .loading { phase = .connected }
        }
    }

    private func linkLost() {
        isLinked = false
        lastTransparencyLevel = 3
        phase = .disconnected
        state = QCYState()
        address = nil
        pending = nil
        writeTask?.cancel()
        readbackTask?.cancel()
    }

    private func settle(after delay: Duration, _ action: @escaping @MainActor () -> Void) {
        settleTask?.cancel()
        settleTask = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            action()
        }
    }
}

// MARK: - Leitura

extension QCYViewModel {
    var ancChoice: QCYANCChoice? { state.ancScene.flatMap(QCYANCChoice.init(scene:)) }
    var ancSelection: QCYANCChoice? {
        if case .anc(let target)? = pending { return target }
        return ancChoice
    }
    var isLDACOn: Bool {
        if case .ldac(let value)? = pending { return value }
        return state.isLDACEnabled ?? false
    }
    var isGameOn: Bool {
        if case .game(let value)? = pending { return value }
        return state.isLowLatencyEnabled ?? false
    }
    var soundEffect: QCYSoundEffect? {
        if case .soundEffect(let target)? = pending { return target }
        return state.soundEffect
    }
    var isVocalBoostAvailable: Bool { state.ancScene?.mode == 0x03 }
    var isVocalBoostOn: Bool {
        if case .vocalBoost(let enabled)? = pending { return enabled }
        return state.ancScene?.mode == 0x03 && state.ancScene?.subScene == 0x02
    }
    var balance: UInt8 {
        if case .balance(let target)? = pending { return target }
        return state.balance ?? 50
    }
    var keyMap: [QCYGesture: QCYKeyFunction] {
        var map = state.keyMap
        if case .key(let gesture, let function)? = pending {
            map[gesture] = function
        }
        return map
    }
    var powerOff: QCYPowerOff? {
        if case .powerOff(let target)? = pending { return target }
        return state.powerOff
    }
    var toneVolume: QCYToneVolume? {
        if case .toneVolume(let target)? = pending { return target }
        return state.toneVolume
    }
    var isWearDetectionAvailable: Bool { state.wearDetection != nil }
    var isWearDetectionOn: Bool {
        if case .wearDetection(let enabled)? = pending { return enabled }
        return state.wearDetection?.isEnabled ?? false
    }
    var areControlsDisabled: Bool { isReadOnly || phase != .connected || pending != nil }

    var isCharging: Bool {
        phase == .connected && (state.left?.isCharging == true || state.right?.isCharging == true)
    }

    var menuBarText: String {
        let left = phase == .connected ? state.left.map { "\($0.percent)%" } ?? "—" : "—"
        let right = phase == .connected ? state.right.map { "\($0.percent)%" } ?? "—" : "—"
        return "L \(left) · R \(right)"
    }
}
