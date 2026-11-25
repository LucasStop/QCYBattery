# Changelog

Formato [Keep a Changelog](https://keepachangelog.com/pt-BR/1.1.0/), em português, uma seção por versão publicada. Cada PR `feat` ou `fix` traz a própria seção, com o que mudou e por quê; os demais tipos não entram. Seções: Adicionado, Alterado, Corrigido, Removido.

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
