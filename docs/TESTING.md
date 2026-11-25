# Testes — QCYBattery

Status: aprovado em 2026-11-25

| Parte | Risco | Nível | Onde | Quando |
|---|---|---|---|---|
| Modelo da janela | Escrita sem confirmação, rollback que não volta, controle habilitado em somente leitura, estado antigo depois de link caído, rótulo da barra de menu, estado de carga, efeitos de som, voz reforçada só na transparência, balanço (commit, reset, clamp e formatação), remapeamento de gestos (eco, rollback, isolamento por célula e idempotência) e ajustes do fone (desligamento automático, volume dos avisos em 4 passos, detecção de uso preservando campos auxiliares e sem escrita antes da leitura) | unitário com link falso | `QCYBatteryTests/QCYViewModelTests.swift`, `QCYBatteryTests/QCYSoundViewModelTests.swift`, `QCYBatteryTests/QCYTouchViewModelTests.swift`, `QCYBatteryTests/QCYAdjustmentsViewModelTests.swift` | local, PR |
| Preferências de presença, login e alertas | Desligar as duas visibilidades ao mesmo tempo, mapeamento para `NSApplication.ActivationPolicy`, persistência (visibilidade e alertas 20%/10%), reflexo do status real do login e pedido de permissão de notificação só ao ligar um switch (nunca no lançamento) | unitário com fakes (`ActivationPolicyApplying`, `LaunchAtLoginControlling`, `BatteryNotifying`) | `QCYBatteryTests/PreferencesModelTests.swift` | local, PR |
| Alertas de bateria baixa | Disparo único em 20% e 10% por lado, não repetição, rearme ao carregar ou acima da histerese (`+5%`), lado `nil`/`0` ignorado, switch desligado não notifica, crítico vence aviso no mesmo evento e integração com `QCYViewModel` sem notificar de verdade | unitário puro + `QCYViewModel` com fake (`BatteryNotifying`) | `QCYBatteryTests/BatteryAlertPolicyTests.swift` | local, PR |
| App Intents | Escrita sem esperar eco, timeout sem conexão (falha legível sem valor falso na bateria), rollback/queda de link durante escrita, idempotência, bloqueio de escrita em somente leitura (preservando leitura de bateria) e mapeamento dos `AppEnum`s | unitário no `QCYIntentRunner` e `AppEnum`s com link falso | `QCYBatteryTests/QCYIntentsTests.swift` | local, PR |
| Protocolo | Byte mal lido | unitário com bytes reais | no QCYKit (`QCYProtocolTests`) | PR do QCYKit |
| Vínculo real com o fone | Permissão, GATT, escrita | smoke manual | `tools/qcyctl` do QCYKit e o app instalado | à mão, com o Lucas presente |

- Rodar: `xcodebuild test -scheme QCYBattery -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`.
- CoreBluetooth e escrita no fone não entram no CI.
- `#Preview` no fim de cada view, com fakes em `QCYBattery/QCYPreviewSupport.swift`; não é teste, o CI só garante que compila.
