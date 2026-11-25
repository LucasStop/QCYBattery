# Arquitetura — QCYBattery

Status: rascunho, aguardando aprovação do Lucas

| Parte | Faz | Código |
|---|---|---|
| Protocolo e cliente BLE | Advertising `0x521C`, canal GATT `A001`, estado acumulado, escrita | pacote [QCYKit](https://github.com/LucasStop/QCYKit) (`QCYClient`, `QCYState`, `QCYPacket`, `QCYAdvertisement`) |
| Modelo da janela | Fase da conexão, escrita otimista confirmada por eco, rollback por timeout, somente leitura | [QCYBattery/QCYViewModel.swift](../QCYBattery/QCYViewModel.swift), protocolo `QCYLink` |
| Janela | Anéis L/R, controles, detalhes, banners de erro e sem conexão (T12) | [QCYBattery/QCYView.swift](../QCYBattery/QCYView.swift) |

## Decisões
- App separado do LogiBattery (ADR 0005 de lá): o PRD do LogiBattery exclui protocolo de terceiro da lista de aparelhos, e os controles não cabem no popover.
- Repo próprio desde 2026-11-25 (ADR 0008 do LogiBattery): versão, CHANGELOG e release independentes; o protocolo é pacote compartilhado com o LogiBattery, que só lê.
- `QCYClient` é o `QCYLink` de verdade (`extension QCYClient: QCYLink`); testes e preview usam link falso.
- Dependência do QCYKit por tag semver (`from:` no `project.yml`).
