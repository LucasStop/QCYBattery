# Dados — QCYBattery

Status: aprovado em 2026-11-25

Estado do fone (bateria, firmware, controles, gestos e ajustes) vem do fone a cada conexão e vive só em memória no `QCYViewModel`. O app persiste apenas preferências locais do usuário em `UserDefaults.standard` via `PreferencesModel`:

| Chave (`UserDefaults`) | Tipo | Padrão | Uso |
|---|---|---|---|
| `preferences.showInMenuBar` | `Bool` | `true` | Visibilidade na barra de menu (US-06) |
| `preferences.showInDock` | `Bool` | `true` | Visibilidade no Dock e Cmd+Tab (US-06) |
| `preferences.lowBatteryAlert` | `Bool` | `true` | Alerta de bateria baixa em 20% por lado (US-11) |
| `preferences.criticalBatteryAlert` | `Bool` | `true` | Alerta crítico de bateria em 10% por lado (US-11) |

- Dado pessoal: o MAC de controle aparece na seção de detalhes (US-04) e não vai para log nem para o texto das notificações.
- Migração e retenção: chaves ausentes assumem o padrão `true`; se `showInMenuBar` e `showInDock` estiverem ambos `false`, o app recupera mantendo a barra de menu ligada.
