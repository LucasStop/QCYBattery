import Carbon.HIToolbox
import Foundation

/// Erros de registro do atalho global do ANC via Carbon `RegisterEventHotKey`.
enum GlobalHotKeyError: Error, LocalizedError, Equatable, Sendable {
    case missingModifiers
    case alreadyRegistered
    case registrationFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .missingModifiers:
            String(localized: "qcy.hotkey.error.missingModifiers")
        case .alreadyRegistered:
            String(localized: "qcy.hotkey.error.alreadyRegistered")
        case .registrationFailed:
            String(localized: "qcy.hotkey.error.registrationFailed")
        }
    }
}

/// Abstração do registro de atalho global para os testes usarem um fake sem tocar no Carbon.
@MainActor
protocol GlobalHotKeyRegistering: AnyObject {
    var onTrigger: (@MainActor () -> Void)? { get set }
    func register(_ shortcut: MacroKeyShortcut) throws
    func unregister()
}

/// Implementação nula usada em previews e testes que não exercitam o registro de atalho.
@MainActor
final class NoOpGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    var onTrigger: (@MainActor () -> Void)?
    func register(_ shortcut: MacroKeyShortcut) throws {}
    func unregister() {}
}

/// Registra o atalho global de ANC via Carbon `RegisterEventHotKey` (não requer permissão de Acessibilidade).
/// Usa `kEventHotKeyExclusive` para detectar conflito com atalhos já registrados por outros apps ou pelo sistema.
@MainActor
final class CarbonGlobalHotKeyRegistrar: GlobalHotKeyRegistering {
    var onTrigger: (@MainActor () -> Void)?

    // Assinatura ASCII 'QCYB'.
    private static let hotKeySignature: OSType = 0x51435942

    nonisolated(unsafe) private var eventHandlerRef: EventHandlerRef?
    nonisolated(unsafe) private var hotKeyRef: EventHotKeyRef?
    private var activeHotKeyID: UInt32 = 0
    private var nextHotKeyID: UInt32 = 1
    private var currentShortcut: MacroKeyShortcut?

    deinit {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
        }
    }

    func register(_ shortcut: MacroKeyShortcut) throws {
        guard !shortcut.modifiers.isEmpty else {
            throw GlobalHotKeyError.missingModifiers
        }
        if shortcut == currentShortcut, hotKeyRef != nil {
            return
        }

        try installEventHandlerIfNeeded()

        let candidateID = nextHotKeyID
        nextHotKeyID &+= 1
        if nextHotKeyID == 0 {
            nextHotKeyID = 1
        }

        let hotKeyID = EventHotKeyID(signature: Self.hotKeySignature, id: candidateID)
        var newRef: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(shortcut.keyCode),
            Self.carbonModifiers(from: shortcut.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            OptionBits(kEventHotKeyExclusive),
            &newRef
        )

        guard status == noErr, let registeredRef = newRef else {
            if status == OSStatus(eventHotKeyExistsErr) {
                throw GlobalHotKeyError.alreadyRegistered
            }
            throw GlobalHotKeyError.registrationFailed(status)
        }

        if let previousRef = hotKeyRef {
            UnregisterEventHotKey(previousRef)
        }
        hotKeyRef = registeredRef
        activeHotKeyID = candidateID
        currentShortcut = shortcut
    }

    func unregister() {
        if let previousRef = hotKeyRef {
            UnregisterEventHotKey(previousRef)
            hotKeyRef = nil
        }
        activeHotKeyID = 0
        currentShortcut = nil
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
            eventHandlerRef = nil
        }
    }

    static func carbonModifiers(from modifiers: Set<MacroKeyModifier>) -> UInt32 {
        var flags: UInt32 = 0
        if modifiers.contains(.command) { flags |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { flags |= UInt32(shiftKey) }
        if modifiers.contains(.option) { flags |= UInt32(optionKey) }
        if modifiers.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }

    private func installEventHandlerIfNeeded() throws {
        guard eventHandlerRef == nil else { return }
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        let userData = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let event, let userData else {
                    return OSStatus(eventNotHandledErr)
                }
                var hotKeyID = EventHotKeyID()
                let paramStatus = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard paramStatus == noErr,
                      hotKeyID.signature == CarbonGlobalHotKeyRegistrar.hotKeySignature else {
                    return OSStatus(eventNotHandledErr)
                }
                let registrar = Unmanaged<CarbonGlobalHotKeyRegistrar>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                let receivedID = hotKeyID.id
                Task { @MainActor in
                    registrar.handleHotKeyEvent(id: receivedID)
                }
                return noErr
            },
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )
        guard status == noErr else {
            throw GlobalHotKeyError.registrationFailed(status)
        }
    }

    private func handleHotKeyEvent(id: UInt32) {
        guard id == activeHotKeyID else { return }
        onTrigger?()
    }
}
