# PRD — QCYBattery

## Problema
O macOS mostra um número só de bateria para o QCY MeloBuds Pro, às vezes errado (100% com o fone em 91–92%), e não dá acesso a cancelamento de ruído, LDAC ou modo jogo sem o app do celular.

## Histórias
| ID | História | Critério de aceite |
|---|---|---|
| US-01 | Como dono do fone, quero ver a bateria de cada lado, para saber qual vai acabar primeiro | Dado o fone por perto e a permissão de Bluetooth, quando abro o app, então vejo dois anéis (L e R) com a porcentagem e o raio quando carrega; lado sem leitura mostra "—", nunca 0% |
| US-02 | Como dono do fone, quero trocar o modo de ruído, LDAC e modo jogo pelo Mac | Dado o fone conectado, quando escolho ANC, normal ou transparência, ou ligo LDAC ou modo jogo, então o controle fica em "aplicando" até o eco do fone; sem eco no tempo ou com o link caído, volta ao valor anterior e mostra o erro; LDAC avisa que o áudio cai por um instante |
| US-03 | Como dono do fone, quero um modo só leitura, para olhar sem risco de mexer no fone | Dado o app aberto com `--read-only`, então os controles aparecem desabilitados e nada é escrito |
| US-04 | Como dono do fone, quero ver firmware e MAC de controle, para diagnóstico | Dado o fone conectado, então a seção de detalhes mostra firmware por lado e o MAC |

## Fora de escopo
- Bateria do estojo: o firmware 2.0.6 não expõe. O terceiro anel entra se algum firmware reportar.
- Modo simples `0x0C`: não responde neste modelo.
- Barra de menu, widget e histórico (o LogiBattery já mostra L/R).
