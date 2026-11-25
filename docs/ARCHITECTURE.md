# Arquitetura — QCYBattery

Status: aprovado em 2026-11-25

| Parte | Faz | Código | Status |
|---|---|---|---|
| Protocolo e cliente BLE | Advertising `0x521C`, canal GATT `A001`, estado acumulado, escrita | pacote [QCYKit](https://github.com/LucasStop/QCYKit) (`QCYClient`, `QCYState`, `QCYPacket`, `QCYAdvertisement`) | implementado |
| Modelo da janela | Fase da conexão, escrita otimista confirmada por eco, rollback por timeout, somente leitura | [QCYBattery/QCYViewModel.swift](../QCYBattery/QCYViewModel.swift), protocolo `QCYLink` | implementado |
| Janela | Anéis L/R, controles, detalhes, banners de erro e sem conexão (T12); abas Som, Gestos e Ajustes (planejadas) | [QCYBattery/QCYView.swift](../QCYBattery/QCYView.swift) | implementado (abas novas: planejado) |
| Cena de barra de menu | Item na barra de menu com popover (anéis L/R, seletor de ANC, preset de som, "Abrir QCYBattery"), visibilidade barra de menu/Dock e abrir no login | — | planejado |
| Módulo de Macro | Execução de ações "Macro no Mac" acionadas por gestos: atalho de teclado (`CGEvent`), atalho do Atalhos (`shortcuts run`), abrir app/URL e script shell/AppleScript | — | planejado |
| App Intents | Intents para o app Atalhos: definir modo de ruído, definir efeito de som e consultar bateria | — | planejado |
| Regras de contexto | Atalho global de ANC, troca automática por chamada em andamento e modo Foco, e notificações de bateria baixa por lado (20% e 10%) | — | planejado |

## Decisões
- App separado do LogiBattery (ADR 0005 de lá): o PRD do LogiBattery exclui protocolo de terceiro da lista de aparelhos, e os controles não cabem no popover.
- Repo próprio desde 2026-11-25 (ADR 0008 do LogiBattery): versão, CHANGELOG e release independentes; o protocolo é pacote compartilhado com o LogiBattery, que só lê.
- `QCYClient` é o `QCYLink` de verdade (`extension QCYClient: QCYLink`); testes e preview usam link falso.
- Dependência do QCYKit por tag semver (`from:` no `project.yml`).
- Saída do App Sandbox (proposta em [docs/adr/0001-sair-do-app-sandbox.md](adr/0001-sair-do-app-sandbox.md)): macros no Mac exigem executar scripts, enviar eventos `CGEvent` e rodar `shortcuts run`, o que requer sair do App Sandbox; o sandbox permanece ativo até o PR que implementa as macros.
- Gestos suportados pelo firmware (questão em aberto): quais gestos de toque o firmware aceita para remapeamento ainda será medido em issue no [QCYKit](https://github.com/LucasStop/QCYKit).
