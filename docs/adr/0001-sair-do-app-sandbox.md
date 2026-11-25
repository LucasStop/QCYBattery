# ADR 0001 — Saída do App Sandbox para macros no Mac

- Status: aceita (2026-11-25)
- Data: 2026-11-25

## Contexto
O QCYBattery é um app de uso pessoal distribuído localmente (assinatura local com o time `69D4S5TF8S`, instalado em `~/Applications`) e mantém o bundle id fixo `com.lucasstop.QCYBattery`, pois alterá-lo faz o macOS perder a permissão de Bluetooth já concedida. Atualmente o app roda dentro do App Sandbox.

O PRD prevê a US-08 (Módulo de Macro), que permite associar gestos do fone a ações "Macro no Mac":
1. executar scripts shell (`/bin/zsh -c`) e AppleScript (`osascript`) via `Process`;
2. enviar atalhos de teclado via `CGEvent` (que exige permissão de Acessibilidade);
3. rodar atalhos do app Atalhos via `shortcuts run`;
4. abrir aplicativos e URLs arbitrários via `NSWorkspace.open`.

Nenhuma dessas quatro ações funciona dentro do App Sandbox, e entitlements de `temporary-exception` não são viáveis para execução de scripts arbitrários definidos pelo usuário.

## Decisão
- O QCYBattery sairá do App Sandbox removendo `com.apple.security.app-sandbox` do arquivo de entitlements, mantendo `com.apple.security.device.bluetooth` e o hardened runtime ativos.
- A remoção do App Sandbox acontece somente no PR que implementar as macros no Mac (US-08), nunca antes; até lá, o App Sandbox permanece ativo.

## Alternativas consideradas
- Manter o App Sandbox e entregar apenas ações de "abrir URL / Atalhos" via URL schemes: rejeitada porque inviabiliza execução de scripts e envio de atalhos de teclado (`CGEvent`).
- Criar um helper XPC separado fora do sandbox apenas para executar as macros: rejeitada por adicionar mais peças móveis, assinatura e ciclo de vida para um app de um único usuário.

## Consequências
- Positivas: viabiliza todas as ações de macro no Mac (shell, AppleScript, `CGEvent`, `shortcuts run` e `NSWorkspace.open`) dentro do próprio processo do app, sem helper externo.
- Negativas e riscos:
  - Novos avisos de TCC para o usuário: Acessibilidade (para `CGEvent`) e Automação (via `NSAppleEventsUsageDescription`, para AppleScript e controle de outros apps).
  - Scripts passam a rodar com as permissões do usuário no Mac; por isso, o app deve executar apenas o que o Lucas configurou explicitamente e nunca registrar o texto de scripts em logs.
  - Distribuição pela Mac App Store deixa de ser possível sem o App Sandbox (Gatekeeper e notarização continuam funcionando como hoje).
- Rollback: restaurar `com.apple.security.app-sandbox` nos entitlements e remover as ações de macro que dependem de execução fora do sandbox.
