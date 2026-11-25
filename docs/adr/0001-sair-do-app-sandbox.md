# ADR 0001 — Saída do App Sandbox para macros no Mac

- Status: aceita e efetivada (2026-11-25)
- Data: 2026-11-25

## Contexto
O QCYBattery é um app de uso pessoal distribuído localmente (assinatura local com o time `69D4S5TF8S`, instalado em `~/Applications`) e mantém o bundle id fixo `com.lucasstop.QCYBattery`, pois alterá-lo faz o macOS perder a permissão de Bluetooth já concedida. Até a entrada do módulo de macros, o app rodava dentro do App Sandbox.

O PRD prevê a US-08 (Módulo de Macro), que permite associar gestos do fone a ações "Macro no Mac":
1. executar scripts shell (`/bin/zsh -c`) e AppleScript (`osascript`) via `Process`;
2. enviar atalhos de teclado via `CGEvent` (que exige permissão de Acessibilidade);
3. rodar atalhos do app Atalhos via `shortcuts run`;
4. abrir aplicativos e URLs arbitrários via `NSWorkspace.open`.

Nenhuma dessas quatro ações funciona dentro do App Sandbox, e entitlements de `temporary-exception` não são viáveis para execução de scripts arbitrários definidos pelo usuário.

## Decisão
- O QCYBattery sai do App Sandbox removendo `com.apple.security.app-sandbox` de `QCYBattery/QCYBattery.entitlements`, mantendo `com.apple.security.device.bluetooth` e o hardened runtime (`ENABLE_HARDENED_RUNTIME: YES`) ativos, além de adicionar `com.apple.security.automation.apple-events` e `NSAppleEventsUsageDescription` para permitir AppleScript sob hardened runtime.
- A remoção do App Sandbox foi efetivada no PR do motor de macros no Mac (US-08, issue #29).

## Alternativas consideradas
- Manter o App Sandbox e entregar apenas ações de "abrir URL / Atalhos" via URL schemes: rejeitada porque inviabiliza execução de scripts e envio de atalhos de teclado (`CGEvent`).
- Criar um helper XPC separado fora do sandbox apenas para executar as macros: rejeitada por adicionar mais peças móveis, assinatura e ciclo de vida para um app de um único usuário.

## Consequências (efetivadas)
- Positivas: viabiliza todas as ações de macro no Mac (shell, AppleScript, `CGEvent`, `/usr/bin/shortcuts run` com argumentos em array e `NSWorkspace`) dentro do próprio processo do app, sem helper externo.
- Negativas e riscos mitigados na implementação:
  - Avisos de TCC sob demanda: Acessibilidade é consultada/solicitada apenas quando uma ação `.keyboardShortcut` roda pela primeira vez (nunca no lançamento do app); Automação (`NSAppleEventsUsageDescription`) aparece apenas quando um AppleScript do usuário controla outro aplicativo.
  - Scripts rodam com as permissões do usuário no Mac, com `stdin` fechado (`/dev/null`), timeout de 10 s (`SIGTERM` seguido de `SIGKILL`) e saída drenada com teto de 64 KB. `MacroStore` e `MacroRunner` nunca registram texto de script, argumentos ou saída em logs ou erros — apenas o `UUID` da macro e o código de resultado tipado.
  - Distribuição pela Mac App Store deixa de ser possível sem o App Sandbox (Gatekeeper e notarização continuam funcionando como hoje).
- Rollback: restaurar `com.apple.security.app-sandbox` nos entitlements, remover `com.apple.security.automation.apple-events` e retirar o módulo `QCYBattery/Macro/`.
