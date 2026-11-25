import AppIntents

/// Atalhos prontos expostos ao app Atalhos, Spotlight e Siri com frases localizadas em pt-BR e en.
struct QCYAppShortcuts: AppShortcutsProvider {
    static var shortcutTileColor: ShortcutTileColor { .teal }

    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SetNoiseModeIntent(),
            phrases: [
                "Definir modo de ruído no \(.applicationName)",
                "Mudar modo de ruído para \(\.$mode) no \(.applicationName)"
            ],
            shortTitle: "qcy.intent.setNoiseMode.shortTitle",
            systemImageName: "headphones"
        )
        AppShortcut(
            intent: SetSoundEffectIntent(),
            phrases: [
                "Definir efeito de som no \(.applicationName)",
                "Mudar efeito de som para \(\.$effect) no \(.applicationName)"
            ],
            shortTitle: "qcy.intent.setSoundEffect.shortTitle",
            systemImageName: "waveform"
        )
        AppShortcut(
            intent: GetBatteryIntent(),
            phrases: [
                "Ver bateria no \(.applicationName)",
                "Consultar bateria no \(.applicationName)"
            ],
            shortTitle: "qcy.intent.getBattery.shortTitle",
            systemImageName: "battery.100"
        )
    }
}
