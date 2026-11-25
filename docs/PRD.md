# PRD — QCYBattery

## Problema
O macOS mostra um número só de bateria para o QCY MeloBuds Pro, às vezes errado (100% com o fone em 91–92%), e não dá acesso a cancelamento de ruído, LDAC ou modo jogo sem o app do celular.

## Histórias
| ID | História | Critério de aceite | Status |
|---|---|---|---|
| US-01 | Como dono do fone, quero ver a bateria de cada lado, para saber qual vai acabar primeiro | Dado o fone por perto e a permissão de Bluetooth, quando abro o app, então vejo dois anéis (L e R) com a porcentagem e o raio quando carrega; lado sem leitura mostra "—", nunca 0% | implementado |
| US-02 | Como dono do fone, quero trocar o modo de ruído, LDAC e modo jogo pelo Mac | Dado o fone conectado, quando escolho ANC, normal ou transparência, ou ligo LDAC ou modo jogo, então o controle fica em "aplicando" até o eco do fone; sem eco no tempo ou com o link caído, volta ao valor anterior e mostra o erro; LDAC avisa que o áudio cai por um instante | implementado |
| US-03 | Como dono do fone, quero um modo só leitura, para olhar sem risco de mexer no fone | Dado o app aberto com `--read-only`, então os controles aparecem desabilitados e nada é escrito | implementado |
| US-04 | Como dono do fone, quero ver firmware e MAC de controle, para diagnóstico | Dado o fone conectado, então a seção de detalhes mostra firmware por lado e o MAC | implementado |
| US-05 | Como dono do fone, quero acessar bateria, ANC e preset de som pela barra de menu | Dado o item da barra de menu ativo, quando clico nele, então abre um popover com anéis de bateria L/R, seletor de ANC, preset de som e ação "Abrir QCYBattery" (preset de som pendente do QCYKit 0.2.0) | implementado |
| US-06 | Como usuário do Mac, quero escolher onde o app aparece e se abre no login | Dado os ajustes do app, quando configuro visibilidade na barra de menu, visibilidade no Dock e "Abrir no login", então pelo menos uma das visibilidades (barra de menu ou Dock) permanece sempre ativa e a preferência de login é respeitada | implementado |
| US-07 | Como dono do fone, quero ajustar o som em uma aba dedicada | Dado o fone conectado, quando abro a aba Som, então posso escolher os 4 presets medidos de efeito (Espacial, Padrão, Pop, Graves pesados), ativar voz reforçada na transparência e ajustar o balanço de canal com opção de reset (2ª página e EQ customizado fora por não terem sido medidos no firmware) | implementado |
| US-08 | Como dono do fone, quero remapear os gestos de toque de cada lado para funções do fone ou macros no Mac | Dado o fone conectado, quando abro a aba Gestos e escolho um gesto por lado, então posso atribuir uma função do fone ou uma "Macro no Mac" (atalho de teclado, atalho do app Atalhos, abrir app/URL ou script shell/AppleScript) | planejado |
| US-09 | Como dono do fone, quero configurar desligamento automático, volume do bipe e detecção de uso na aba Ajustes | Dado o fone conectado, quando altero desligamento automático, volume do bipe ou detecção de uso na aba Ajustes, então a escrita segue a confirmação por eco do fone | planejado |
| US-10 | Como dono do fone, quero trocar o ANC por atalho global e por regras de contexto | Dado as regras configuradas na aba Ajustes, quando aciono o atalho global de ANC ou entro em chamada em andamento ou modo Foco, então o app aplica o modo de ANC configurado para o contexto | planejado |
| US-11 | Como dono do fone, quero receber notificação de bateria baixa por lado | Dado o fone conectado e a permissão de notificação, quando a bateria de L ou R atinge 20% ou 10%, então recebo uma notificação identificando o lado e o nível | planejado |
| US-12 | Como usuário de automações, quero controlar e consultar o fone pelo app Atalhos | Dado o app instalado, quando crio um atalho no app Atalhos, então estão disponíveis as App Intents para definir modo de ruído, definir efeito de som e consultar bateria | planejado |

## Questões em aberto
- Gestos suportados: ainda será medido no firmware (issue no QCYKit) quais gestos de toque o QCY MeloBuds Pro aceita para remapeamento.
- App Sandbox: executar macros no Mac (script shell/AppleScript, `CGEvent` e `shortcuts run`) exige sair do App Sandbox; proposta em [docs/adr/0001-sair-do-app-sandbox.md](adr/0001-sair-do-app-sandbox.md) (sandbox permanece ativo até o PR que implementa as macros).

## Fora de escopo
- Bateria do estojo: o firmware 2.0.6 não expõe. O terceiro anel entra se algum firmware reportar.
- Modo simples `0x0C`: não responde neste modelo.
- Widget e histórico (o LogiBattery já mostra L/R).
