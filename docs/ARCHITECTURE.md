# Arquitetura — QCYBattery

Status: aprovado em 2026-11-25

| Parte | Faz | Código | Status |
|---|---|---|---|
| Protocolo e cliente BLE | Advertising `0x521C`, canal GATT `A001`, estado acumulado, escrita | pacote [QCYKit](https://github.com/LucasStop/QCYKit) (`QCYClient`, `QCYState`, `QCYPacket`, `QCYAdvertisement`) | implementado |
| Modelo da janela | Fase da conexão, escrita otimista confirmada por eco, rollback por timeout, somente leitura | [QCYBattery/QCYViewModel.swift](../QCYBattery/QCYViewModel.swift), protocolo `QCYLink` | implementado |
| Janela | Barra de abas segmentada (Status / Som / Toques / Ajustes); Status com anéis L/R, controles, detalhes e banners (T12); Som com grade 2×2 de efeitos medidos, voz reforçada na transparência e slider de balanço L/R (T14); Toques com desenho dos fones L/R e remapeamento de 1/2/3 toques para as 9 funções do fone (T15); Ajustes com seção Fone (desligamento automático, volume dos avisos em 4 níveis e detecção de uso) e seção App compartilhada com a cena `Settings` (T16) | [QCYBattery/QCYView.swift](../QCYBattery/QCYView.swift), [QCYBattery/QCYSoundView.swift](../QCYBattery/QCYSoundView.swift), [QCYBattery/QCYTouchView.swift](../QCYBattery/QCYTouchView.swift), [QCYBattery/QCYAdjustmentsView.swift](../QCYBattery/QCYAdjustmentsView.swift) | implementado |
| Cena de barra de menu | Item na barra de menu com popover (anéis L/R, seletor de ANC, "Abrir QCYBattery…" e "Encerrar"; preset de som pendente do QCYKit 0.2.0), visibilidade barra de menu/Dock, política de ativação e abrir no login (`SMAppService`) via cena `Settings` (Cmd+,) | [QCYBattery/QCYBatteryApp.swift](../QCYBattery/QCYBatteryApp.swift), [QCYBattery/QCYMenuBarPopover.swift](../QCYBattery/QCYMenuBarPopover.swift), [QCYBattery/PreferencesModel.swift](../QCYBattery/PreferencesModel.swift), [QCYBattery/QCYSettingsView.swift](../QCYBattery/QCYSettingsView.swift) | implementado |
| Módulo de Macro | Execução de ações "Macro no Mac" acionadas por gestos: atalho de teclado (`CGEvent`), atalho do Atalhos (`shortcuts run`), abrir app/URL e script shell/AppleScript | — | planejado |
| App Intents | Intents para o app Atalhos: definir modo de ruído, definir efeito de som e consultar bateria | — | planejado |
| Regras de contexto | Atalho global de ANC, troca automática por chamada em andamento e modo Foco, e notificações de bateria baixa por lado (20% e 10%) | — | planejado |

## Decisões
- App separado do LogiBattery (ADR 0005 de lá): o PRD do LogiBattery exclui protocolo de terceiro da lista de aparelhos, e os controles não cabem no popover.
- Repo próprio desde 2026-11-25 (ADR 0008 do LogiBattery): versão, CHANGELOG e release independentes; o protocolo é pacote compartilhado com o LogiBattery, que só lê.
- `QCYClient` é o `QCYLink` de verdade (`extension QCYClient: QCYLink`); testes e preview usam link falso.
- Dependência do QCYKit por tag semver (`from:` no `project.yml`).
- Saída do App Sandbox (proposta em [docs/adr/0001-sair-do-app-sandbox.md](adr/0001-sair-do-app-sandbox.md)): macros no Mac exigem executar scripts, enviar eventos `CGEvent` e rodar `shortcuts run`, o que requer sair do App Sandbox; o sandbox permanece ativo até o PR que implementa as macros.
- Gestos suportados pelo firmware (medido no QCYKit 0.6.0): característica `000D` expõe 6 gestos (1, 2 e 3 toques por lado) com 9 funções (`QCYKeyFunction`); 4 toques e toque longo não são expostos pelo firmware.
