import AppKit
import ApplicationServices
import Foundation
import MediaPlayer

/// Fonte de comandos de mídia vindos do fone/sistema. Permanece inerte quando `activeCommands` é vazio.
@MainActor
protocol GestureSource: AnyObject {
    /// Retorna `true` quando há macro para o comando (capturando-o) e `false` para deixar a mídia agir.
    var onCommand: ((MediaCommand) -> Bool)? { get set }

    func updateActiveCommands(_ commands: Set<MediaCommand>)
    func stop()
}

/// Captura comandos AVRCP/mídia via `MPRemoteCommandCenter` + `MPNowPlayingInfoCenter`.
/// Quando não há macros cadastradas, não habilita comandos nem ocupa o `MPNowPlayingInfoCenter`.
@MainActor
final class RemoteCommandGestureSource: GestureSource {
    var onCommand: ((MediaCommand) -> Bool)?

    private var activeCommands: Set<MediaCommand> = []
    private var registeredTargets: [(command: MPRemoteCommand, token: Any)] = []
    private var isClaimingNowPlaying = false

    func updateActiveCommands(_ commands: Set<MediaCommand>) {
        if commands.isEmpty {
            if !activeCommands.isEmpty || isClaimingNowPlaying || !registeredTargets.isEmpty {
                tearDown()
            }
            return
        }
        guard commands != activeCommands || registeredTargets.isEmpty else { return }

        removeAllTargets()
        activeCommands = commands

        let center = MPRemoteCommandCenter.shared()
        configureCommand(center.togglePlayPauseCommand, for: .play, enabled: commands.contains(.play))
        configureCommand(center.playCommand, for: .play, enabled: commands.contains(.play))
        configureCommand(center.pauseCommand, for: .play, enabled: commands.contains(.play))
        configureCommand(center.nextTrackCommand, for: .next, enabled: commands.contains(.next))
        configureCommand(center.previousTrackCommand, for: .previous, enabled: commands.contains(.previous))

        let infoCenter = MPNowPlayingInfoCenter.default()
        infoCenter.nowPlayingInfo = [MPMediaItemPropertyTitle: "QCYBattery"]
        infoCenter.playbackState = .playing
        isClaimingNowPlaying = true
    }

    func stop() {
        tearDown()
    }

    private func configureCommand(
        _ remoteCommand: MPRemoteCommand,
        for mediaCommand: MediaCommand,
        enabled: Bool
    ) {
        remoteCommand.isEnabled = enabled
        guard enabled else { return }
        let token = remoteCommand.addTarget { [weak self] _ in
            let handled = Self.dispatchToMainActor {
                self?.onCommand?(mediaCommand) ?? false
            }
            return handled ? .success : .noActionableNowPlayingItem
        }
        registeredTargets.append((remoteCommand, token))
    }

    private func tearDown() {
        removeAllTargets()
        activeCommands = []
        if isClaimingNowPlaying {
            let center = MPRemoteCommandCenter.shared()
            center.togglePlayPauseCommand.isEnabled = false
            center.playCommand.isEnabled = false
            center.pauseCommand.isEnabled = false
            center.nextTrackCommand.isEnabled = false
            center.previousTrackCommand.isEnabled = false

            let infoCenter = MPNowPlayingInfoCenter.default()
            infoCenter.nowPlayingInfo = nil
            infoCenter.playbackState = .unknown
            isClaimingNowPlaying = false
        }
    }

    private func removeAllTargets() {
        for entry in registeredTargets {
            entry.command.removeTarget(entry.token)
            entry.command.isEnabled = false
        }
        registeredTargets.removeAll()
    }

    nonisolated private static func dispatchToMainActor(_ block: @MainActor () -> Bool) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated(block)
        }
        return DispatchQueue.main.sync {
            MainActor.assumeIsolated(block)
        }
    }
}

/// Evento decodificado de tecla de mídia `NX_SYSDEFINED` (`subtype == 8`).
struct ParsedMediaKeyEvent: Equatable, Sendable {
    let command: MediaCommand
    let isKeyDown: Bool
    let isRepeat: Bool
}

/// Decodificador puro dos bits `data1` de `NSEvent.EventType.systemDefined` para teclas de mídia.
enum MediaKeyEventParser {
    static let systemDefinedRawType: UInt32 = 14
    static let auxControlButtonsSubtype: Int16 = 8

    private static let keyTypePlay = 16
    private static let keyTypeNext = 17
    private static let keyTypePrevious = 18
    private static let keyTypeFast = 19
    private static let keyTypeRewind = 20

    private static let keyStateDown = 0x0A
    private static let keyStateUp = 0x0B

    static func parse(subtype: Int16, data1: Int) -> ParsedMediaKeyEvent? {
        guard subtype == auxControlButtonsSubtype else { return nil }
        let keyCode = (data1 & 0xFFFF_0000) >> 16
        let keyFlags = data1 & 0x0000_FFFF
        let keyState = (keyFlags & 0xFF00) >> 8
        let isRepeat = (keyFlags & 0x0001) != 0

        guard keyState == keyStateDown || keyState == keyStateUp else { return nil }
        guard let command = mediaCommand(for: keyCode) else { return nil }

        return ParsedMediaKeyEvent(
            command: command,
            isKeyDown: keyState == keyStateDown,
            isRepeat: isRepeat
        )
    }

    private static func mediaCommand(for keyCode: Int) -> MediaCommand? {
        switch keyCode {
        case keyTypePlay: .play
        case keyTypeNext, keyTypeFast: .next
        case keyTypePrevious, keyTypeRewind: .previous
        default: nil
        }
    }
}

/// Captura complementar de teclas de mídia `NX_SYSDEFINED` via `CGEventTap`.
/// Permanece inerte quando não há macros ou enquanto a permissão de Acessibilidade não tiver sido
/// concedida (consulta silenciosa via `AXIsProcessTrusted()`, nunca pedindo permissão no lançamento).
@MainActor
final class MediaKeyEventTapGestureSource: GestureSource {
    var onCommand: ((MediaCommand) -> Bool)?

    private let isAccessibilityTrusted: () -> Bool
    private var activeCommands: Set<MediaCommand> = []
    private var suppressedCommands: Set<MediaCommand> = []
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(isAccessibilityTrusted: @escaping () -> Bool = { AXIsProcessTrusted() }) {
        self.isAccessibilityTrusted = isAccessibilityTrusted
    }

    func updateActiveCommands(_ commands: Set<MediaCommand>) {
        activeCommands = commands
        suppressedCommands.formIntersection(commands)

        if commands.isEmpty || !isAccessibilityTrusted() {
            tearDownTap()
            return
        }
        installTapIfNeeded()
    }

    func stop() {
        activeCommands = []
        suppressedCommands.removeAll()
        tearDownTap()
    }

    private func installTapIfNeeded() {
        guard eventTap == nil else { return }
        let mask = CGEventMask(1 << MediaKeyEventParser.systemDefinedRawType)
        let pointer = Unmanaged.passUnretained(self).toOpaque()

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            guard let userInfo else { return Unmanaged.passUnretained(event) }
            let source = Unmanaged<MediaKeyEventTapGestureSource>.fromOpaque(userInfo).takeUnretainedValue()

            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                MainActor.assumeIsolated {
                    source.reenableTapIfNeeded()
                }
                return Unmanaged.passUnretained(event)
            }

            guard type.rawValue == MediaKeyEventParser.systemDefinedRawType,
                  let nsEvent = NSEvent(cgEvent: event),
                  let parsed = MediaKeyEventParser.parse(
                      subtype: nsEvent.subtype.rawValue,
                      data1: nsEvent.data1
                  ) else {
                return Unmanaged.passUnretained(event)
            }

            let shouldConsume = MainActor.assumeIsolated {
                source.shouldConsumeMediaKey(parsed)
            }
            return shouldConsume ? nil : Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: pointer
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        runLoopSource = source
        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func tearDownTap() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    func shouldConsumeMediaKey(_ parsed: ParsedMediaKeyEvent) -> Bool {
        guard activeCommands.contains(parsed.command) else {
            return false
        }

        if parsed.isKeyDown {
            if parsed.isRepeat {
                return suppressedCommands.contains(parsed.command)
            }
            let captured = onCommand?(parsed.command) ?? false
            if captured {
                suppressedCommands.insert(parsed.command)
            }
            return captured
        }

        return suppressedCommands.remove(parsed.command) != nil
    }

    private func reenableTapIfNeeded() {
        if let tap = eventTap, !activeCommands.isEmpty {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}

/// Combina múltiplas fontes de gesto (`MPRemoteCommandCenter` + `CGEventTap`) sob um único `GestureSource`.
@MainActor
final class CompositeGestureSource: GestureSource {
    var onCommand: ((MediaCommand) -> Bool)? {
        didSet {
            for source in sources {
                source.onCommand = onCommand
            }
        }
    }

    private let sources: [any GestureSource]

    init(
        sources: [any GestureSource] = [
            RemoteCommandGestureSource(),
            MediaKeyEventTapGestureSource()
        ]
    ) {
        self.sources = sources
    }

    func updateActiveCommands(_ commands: Set<MediaCommand>) {
        for source in sources {
            source.updateActiveCommands(commands)
        }
    }

    func stop() {
        for source in sources {
            source.stop()
        }
    }
}
