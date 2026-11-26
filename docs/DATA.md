# Dados — QCYBattery

Status: aprovado em 2026-11-25

Estado do fone (bateria, firmware, controles, gestos e ajustes) vem do fone a cada conexão e vive só em memória no `QCYViewModel`. Localmente no Mac, o app persiste preferências em `UserDefaults.standard` (via `PreferencesModel`) e as macros configuradas pelo usuário em `Application Support` (via `MacroStore`).

## Preferências (`UserDefaults.standard`)

| Chave (`UserDefaults`) | Tipo | Padrão | Uso |
|---|---|---|---|
| `preferences.showInMenuBar` | `Bool` | `true` | Visibilidade na barra de menu (US-06) |
| `preferences.showInDock` | `Bool` | `true` | Visibilidade no Dock e Cmd+Tab (US-06) |
| `preferences.lowBatteryAlert` | `Bool` | `true` | Alerta de bateria baixa em 20% por lado (US-11) |
| `preferences.criticalBatteryAlert` | `Bool` | `true` | Alerta crítico de bateria em 10% por lado (US-11) |
| `preferences.globalANCHotKey` | `Data` (JSON `MacroKeyShortcut`) | ausente (`nil`) | Atalho global de ciclo de ANC (`keyCode` + `modifiers`); ausente = nenhum atalho registrado (US-10) |
| `preferences.contextRule.call.enabled` | `Bool` | `true` | Ativa ou desativa a regra de ANC durante chamada em andamento; desligada mantém o monitor CoreAudio inerte (US-10) |
| `preferences.contextRule.call.scene` | `String` (`QCYANCChoice.rawValue`) | `"transparency"` | Cena aplicada durante chamada em andamento: `"anc"`, `"normal"` ou `"transparency"` (US-10) |

- Migração e retenção de preferências: chaves ausentes assumem o padrão da tabela; se `showInMenuBar` e `showInDock` estiverem ambos `false`, o app recupera mantendo a barra de menu ligada; `globalANCHotKey` corrompido ou sem modificadores volta a `nil`; `contextRule.call.scene` desconhecido volta a `"transparency"`.
- Estado em memória das regras de contexto (US-10): a pilha de contextos ativos, a cena anterior salva para restauração e o último filtro de Foco recebido via `SetFocusFilterIntent` vivem apenas em memória no `ContextRuleCoordinator` / `ContextRulePolicy` e não sobrevivem a reinício do app.

## Macros no Mac (`~/Library/Application Support/QCYBattery/macros.json`)

Primeira persistência fora de `UserDefaults` (US-08), gerenciada por `MacroStore`:

- **Envelope:** objeto JSON com `"version": 1` e `"macros": [Macro]`, gravado com escrita atômica (`.atomic`) e chaves ordenadas. Enquanto nenhuma macro for salva, o arquivo não é criado.
- **Campos de `Macro`:**
  - `id`: `UUID`
  - `name`: `String`
  - `trigger`: `"play"` | `"next"` | `"previous"` (`MediaCommand`; invariante de no máximo uma macro por `trigger`)
  - `action`: objeto discriminado por `"type"`:
    - `"keyboardShortcut"`: `"keyCode"` (`UInt16`, `CGKeyCode`) e `"modifiers"` (`["command" | "shift" | "option" | "control"]`)
    - `"shortcut"`: `"name"` (`String`, nome do atalho no app Atalhos)
    - `"open"`: `"target"` com `"kind"` (`"appPath"` | `"bundleIdentifier"` | `"url"`) e `"value"` (`String` / `URL`)
    - `"script"`: `"kind"` (`"shell"` | `"appleScript"`) e `"source"` (`String`)
- **Recuperação de falhas:** se `macros.json` estiver ilegível, corrompido, com `version` desconhecida ou com `trigger` duplicado, o app ignora o arquivo (carrega lista vazia sem derrubar o processo) e registra apenas o código estático da falha.

## Privacidade e logs
- O MAC de controle aparece apenas na seção de detalhes (US-04) e nunca vai para log nem para o texto das notificações.
- O texto de scripts (`source`), nomes/argumentos de macros, caminhos de apps/URLs e a saída de processos nunca são registrados em log nem incluídos em mensagens de erro: o `MacroRunner` registra somente o `UUID` da macro e o código tipado do resultado.
