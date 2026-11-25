# Changelog

Formato [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), em português, uma seção por versão publicada. Cada PR `feat` ou `fix` traz a própria seção, com o que mudou e por quê; os demais tipos não entram. Seções: Adicionado, Alterado, Corrigido, Removido.

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
