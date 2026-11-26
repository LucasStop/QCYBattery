import CoreAudio
import Foundation

/// Monitor de atividade do microfone padrão (indicador de chamada em andamento), atrás de protocolo para testes.
@MainActor
protocol CallActivityMonitoring: AnyObject {
    var isActive: Bool { get }
    var onChange: (@MainActor (Bool) -> Void)? { get set }
    func start()
    func stop()
}

/// Implementação nula usada em previews e testes que não exercitam CoreAudio.
@MainActor
final class NoOpCallActivityMonitor: CallActivityMonitoring {
    private(set) var isActive = false
    var onChange: (@MainActor (Bool) -> Void)?
    func start() {}
    func stop() {}
}

/// Observa `kAudioDevicePropertyDeviceIsRunningSomewhere` no dispositivo de entrada padrão do macOS via CoreAudio,
/// acompanhando também trocas de dispositivo padrão (`kAudioHardwarePropertyDefaultInputDevice`).
/// Permanece completamente inerte enquanto `start()` não for chamado (ou depois de `stop()`).
@MainActor
final class CoreAudioCallActivityMonitor: CallActivityMonitoring {
    private(set) var isActive = false
    var onChange: (@MainActor (Bool) -> Void)?

    private var isMonitoring = false
    private var observedDeviceID: AudioDeviceID?
    private var systemListenerBlock: AudioObjectPropertyListenerBlock?
    private var deviceListenerBlock: AudioObjectPropertyListenerBlock?

    private static let defaultInputAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultInputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static let deviceRunningAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true

        var address = Self.defaultInputAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.rebindDefaultInputDevice()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
        if status == noErr {
            systemListenerBlock = block
        }

        rebindDefaultInputDevice()
    }

    func stop() {
        guard isMonitoring else { return }
        isMonitoring = false

        detachDeviceListener()

        if let block = systemListenerBlock {
            var address = Self.defaultInputAddress
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                DispatchQueue.main,
                block
            )
            systemListenerBlock = nil
        }

        isActive = false
    }

    private func rebindDefaultInputDevice() {
        guard isMonitoring else { return }
        detachDeviceListener()

        guard let deviceID = Self.defaultInputDeviceID() else {
            updateActiveState(false)
            return
        }

        var address = Self.deviceRunningAddress
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            Task { @MainActor [weak self] in
                self?.refreshDeviceRunningState()
            }
        }
        let status = AudioObjectAddPropertyListenerBlock(
            deviceID,
            &address,
            DispatchQueue.main,
            block
        )
        if status == noErr {
            observedDeviceID = deviceID
            deviceListenerBlock = block
        }

        updateActiveState(Self.isDeviceRunningSomewhere(deviceID))
    }

    private func refreshDeviceRunningState() {
        guard isMonitoring, let deviceID = observedDeviceID else { return }
        updateActiveState(Self.isDeviceRunningSomewhere(deviceID))
    }

    private func updateActiveState(_ newValue: Bool) {
        guard newValue != isActive else { return }
        isActive = newValue
        onChange?(newValue)
    }

    private func detachDeviceListener() {
        if let deviceID = observedDeviceID, let block = deviceListenerBlock {
            var address = Self.deviceRunningAddress
            AudioObjectRemovePropertyListenerBlock(
                deviceID,
                &address,
                DispatchQueue.main,
                block
            )
        }
        observedDeviceID = nil
        deviceListenerBlock = nil
    }

    private static func defaultInputDeviceID() -> AudioDeviceID? {
        var deviceID = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = defaultInputAddress
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        )
        guard status == noErr, deviceID != kAudioObjectUnknown else {
            return nil
        }
        return deviceID
    }

    private static func isDeviceRunningSomewhere(_ deviceID: AudioDeviceID) -> Bool {
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = deviceRunningAddress
        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &running
        )
        guard status == noErr else { return false }
        return running != 0
    }
}
