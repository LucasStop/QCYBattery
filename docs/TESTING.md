# Testes — QCYBattery

Status: aprovado em 2026-11-25

| Parte | Risco | Nível | Onde | Quando |
|---|---|---|---|---|
| Modelo da janela | Escrita sem confirmação, rollback que não volta, controle habilitado em somente leitura, estado antigo depois de link caído, rótulo da barra de menu, estado de carga, efeitos de som, voz reforçada só na transparência e balanço (commit, reset, clamp e formatação) | unitário com link falso | `QCYBatteryTests/QCYViewModelTests.swift`, `QCYBatteryTests/QCYSoundViewModelTests.swift` | local, PR |
| Preferências de presença e login | Desligar as duas visibilidades ao mesmo tempo, mapeamento para `NSApplication.ActivationPolicy`, persistência e reflexo do status real do login | unitário com fakes (`ActivationPolicyApplying`, `LaunchAtLoginControlling`) | `QCYBatteryTests/PreferencesModelTests.swift` | local, PR |
| Protocolo | Byte mal lido | unitário com bytes reais | no QCYKit (`QCYProtocolTests`) | PR do QCYKit |
| Vínculo real com o fone | Permissão, GATT, escrita | smoke manual | `tools/qcyctl` do QCYKit e o app instalado | à mão, com o Lucas presente |

- Rodar: `xcodebuild test -scheme QCYBattery -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- CoreBluetooth e escrita no fone não entram no CI.
- `#Preview` no fim de cada view, com fakes em `QCYBattery/QCYPreviewSupport.swift`; não é teste, o CI só garante que compila.
