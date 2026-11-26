# Changelog

Formato [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), em português, uma seção por versão publicada. Cada PR `feat` ou `fix` traz a própria seção, com o que mudou e por quê; os demais tipos não entram. Seções: Adicionado, Alterado, Corrigido, Removido.

## 0.10.3 - 2026-11-26

### Corrigido

- O app volta a achar o fone sozinho: desconectado, reinicia a busca a cada 10 s, sem mexer na tela. Antes era preciso abrir o popover e clicar em "Procurar de novo", porque o scan do Bluetooth não reporta de novo um fone já visto e o link que o macOS mantém aberto não anuncia.

## 0.10.2 - 2026-11-25

### Corrigido

- A barra de menu lista só os fones com leitura ("L 95%", "R 80%" ou os dois) e mostra só o ícone de fone quando não há conexão. Antes aparecia "R —" ou "L — · R —", ruído num item estreito. O resumo de bateria dos Atalhos mantém o texto completo.

## 0.10.1 - 2026-11-25

### Corrigido

- Com "Mostrar na barra de menu" ligado, Cmd+Q e fechar a janela não encerram mais o app: só fecham as janelas e o ícone da barra de menu continua ativo, como a configuração promete. "Encerrar" no popover, e Cmd+Q com a barra de menu desligada, encerram de verdade.

## 0.10.0 - 2026-11-25

### Adicionado

- Atalho global que cicla o ANC (ANC, Transparência, Normal) de qualquer app, gravado na aba Ajustes; usa o registro de atalho do sistema, que não pede permissão extra. Trocar de cena sem pegar o fone na mão era o pedido mais direto do US-10.
- Regra de ANC por contexto: com o microfone em uso (chamada), o app aplica a cena escolhida, por padrão Transparência, e ao terminar volta à cena de antes, a menos que você tenha trocado o ANC à mão nesse meio tempo, para não desfazer a sua escolha. O monitor de áudio só roda com a regra ligada.
- Filtro de Foco do QCYBattery: em Ajustes do Sistema > Foco > Filtros de Foco o Foco escolhe a cena de ANC e, ao sair, a cena anterior volta. O macOS não deixa um app descobrir qual Foco está ativo de outra forma, por isso a configuração fica lá e não numa lista dentro do app.

## 0.9.3 - 2026-11-25

### Corrigido

- Com um fone só no ouvido, o outro reporta 0% e aparecia como bateria vazia ("R 0%" na barra de menu, anel crítico) e podia disparar o aviso de bateria crítica. Agora 0% vale como "sem leitura": a barra de menu e os anéis mostram "—", o anel fica esmaecido e o aviso ignora aquele lado.

## 0.9.2 - 2026-11-25

### Corrigido

- Controles sem leitura do fone (efeito de som, balanço, volume do bipe, desligamento automático, LDAC e modo jogo) ficam inativos e esmaecidos, como já era o vocal boosted. Antes eles apareciam ativos com um valor padrão inventado, e um toque podia gravar no fone sobre um estado que o app nunca leu.

## 0.9.1 - 2026-11-25

### Corrigido

- O item da barra de menu aparecia só com "L n% · R n%", sem o ícone do fone: o símbolo customizado não é desenhado no rótulo da barra de menu. Agora o rótulo usa o símbolo de fone do sistema, alinhado pela linha de base com os outros itens da barra; as janelas e o popover seguem com o símbolo próprio.

## 0.9.0 - 2026-11-25

### Adicionado

- Editor de macro na aba Toques: o menu de cada gesto ganha "Macro no Mac…", com nome, comando de mídia, tipo da ação (atalho de teclado, Atalho, app/URL ou script), botão Testar e o aviso de que scripts rodam com as suas permissões. Sem a tela, o motor de macros da versão anterior não tinha como ser usado. Ao salvar, o app grava no gesto a função de mídia que serve de gatilho, e a música perde essa função naquele gesto; o texto do script nunca aparece em log.

## 0.8.1 - 2026-11-25

### Corrigido

- As abas Som e Ajustes mostravam "O fone não respondeu" ao mudar efeito, balanço, desligamento automático, volume dos avisos ou detecção de uso, embora o fone aplicasse a mudança: ele não avisa o valor novo nesses comandos, e o app só confirmava por aviso. Agora o app relê o estado logo depois de escrever e confirma pela leitura; uma escrita que realmente falha continua voltando ao valor anterior.

## 0.8.0 - 2026-11-25

### Adicionado

- Motor de macros no Mac: um comando de mídia vindo do fone pode disparar um atalho de teclado, um Atalho do app Atalhos, abrir um app ou URL, ou rodar um script shell ou AppleScript. Ainda não há tela para criar macros (vem no próximo PR). Para isso o app saiu do App Sandbox (ADR 0001), pois script, teclas e `shortcuts` não rodam dentro dele; o hardened runtime continua ligado. O app só executa o que você configurar, e o texto de script, argumentos e saída nunca vão para log.

## 0.7.0 - 2026-11-25

### Adicionado

- Ações no app Atalhos (e Spotlight/Siri) para definir o modo de ruído, definir o efeito de som e consultar a bateria de cada lado: dá para automatizar o fone (por exemplo, trocar para transparência ao chegar em casa) sem abrir o app. A escrita só é dada como feita depois que o fone confirma; sem conexão em 5 s ou sem eco, a ação falha com uma mensagem legível em vez de fingir sucesso.

## 0.6.0 - 2026-11-25

### Adicionado

- Notificação de bateria baixa por lado, em 20% (aviso) e 10% (crítico), com os dois limites ligáveis na aba Ajustes: dá para saber que um dos fones está acabando sem olhar a janela. Cada lado avisa uma vez por limite e só avisa de novo depois de carregar ou subir acima do limite com folga de 5 pontos, para não repetir quando a leitura oscila. A permissão de notificação só é pedida ao ligar um dos avisos.

## 0.5.0 - 2026-11-25

### Adicionado

- Aba Ajustes na janela principal com o desligamento automático do fone (desativado, 15, 30, 60 ou 90 min), o volume dos avisos em quatro níveis e a detecção de uso, além das preferências do app (barra de menu, Dock e abrir ao iniciar sessão): antes só dava para mexer no fone pelo app oficial da QCY. A detecção de uso mantém o controle de música e o ANC ao colocar o fone como já estavam, e o volume só grava ao soltar o controle. Atalho global, regras de ANC por contexto e alertas de bateria vêm depois.

## 0.4.0 - 2026-11-25

### Adicionado

- Aba Toques na janela principal para remapear os gestos do fone (1, 2 e 3 toques, esquerdo e direito) entre as funções que o fone aceita: antes só dava para mudar isso no app oficial da QCY. O fone não expõe 4 toques nem toque longo, então esses não aparecem; a troca só vale depois que o fone confirma a escrita.

## 0.3.0 - 2026-11-25

### Adicionado

- Aba Som na janela principal, com os efeitos de som do fone (Espacial, Padrão, Pop e Graves pesados), a voz reforçada e o balanço entre esquerdo e direito: antes só dava para mexer nisso no app oficial da QCY. A voz reforçada só vale na transparência (o fone não tem esse ajuste fora dela), então o botão fica desabilitado nos outros modos, e o balanço só grava ao soltar o controle para não inundar o link.

## 0.2.0 - 2026-11-25

### Adicionado

- Item na barra de menu com o resumo "L 90% · R 91%" e um popover com os anéis de bateria, o seletor de ANC e os botões Abrir e Encerrar: dá para ver a bateria e trocar o ruído sem abrir a janela. O preset de som entra quando o QCYKit expuser os comandos de som.
- Preferências para mostrar o app na barra de menu e no Dock (sempre ao menos uma das duas ligada, para o app nunca ficar sem entrada) e para abrir no login, numa janela de Ajustes mínima (Cmd+,). A aba de Ajustes completa vem depois.

## 0.1.0 - 2026-11-25

### Alterado

- O app saiu do repositório do LogiBattery para um repositório próprio, com versão e release independentes: antes qualquer mudança no fone subia a versão do LogiBattery e vice-versa. O protocolo do fone vem do pacote QCYKit 0.1.0. Comportamento da janela igual ao do LogiBattery 0.5.0.
