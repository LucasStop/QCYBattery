# Backlog — QCYBattery

Fonte das issues iniciais. Depois de criadas, a issue no GitHub é a fonte; este arquivo vira histórico.

Status: expansão de escopo registrada na issue #7. O app nasceu pronto da separação do LogiBattery (issue #1, PR #2, release `v0.1.0`); histórico anterior nas issues de lá.

## Itens planejados (issue #7)
- Barra de menu com popover (anéis L/R, seletor de ANC, preset de som, "Abrir QCYBattery"), visibilidade configurável entre barra de menu e Dock (ao menos uma ativa) e opção de abrir no login.
- Aba Som: presets de efeito, vocal realçado, balanço de canal com reset e EQ customizado (se o firmware suportar).
- Aba Gestos: remapeamento por lado dos gestos de toque para funções do fone ou para "Macro no Mac" (atalho de teclado, atalho do app Atalhos, abrir app/URL, script shell/AppleScript). Depende de medição no QCYKit sobre quais gestos o firmware aceita.
- Aba Ajustes: desligamento automático, volume do bipe, detecção de uso, atalho global de ANC, regras de ANC por contexto (chamada em andamento, modo Foco) e notificação de bateria baixa por lado em 20% e 10%.
- App Intents para o app Atalhos: definir modo de ruído, definir efeito de som e consultar bateria.
- Decisão pendente (ADR): saída do App Sandbox para viabilizar macros no Mac (script, `CGEvent`, `shortcuts run`).
