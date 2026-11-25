# Design system — QCYBattery

Status: aprovado em 2026-11-25

Herda os tokens do [LogiBattery](https://github.com/LucasStop/LogiBattery/blob/main/DESIGN.md): cores de nível (`BatteryLevel.color` em [QCYBattery/BatteryLevel.swift](QCYBattery/BatteryLevel.swift), mesmos hex de lá), tipografia do sistema, `accentColor` do macOS, claro e escuro. Mudou lá e deve valer aqui: copiar no mesmo PR que mexer no app.

## Cores de nível
| Nível | Claro | Escuro |
|---|---|---|
| normal (≥ 20%) | `#1F9D55` | `#34C77B` |
| baixo (< 20%) | `#B7791F` | `#F2B13C` |
| crítico (< 10%) | `#C53030` | `#FF6B6B` |
| sem leitura | `.secondary` | `.secondary` |

## Componentes
| Componente | Variantes | Tamanhos | Estados cobertos | Código | Teste |
|---|---|---|---|---|---|
| Seletor segmentado do ANC (T12, #150) | três botões de largura igual dentro de um trilho `.quaternary` (raio 8, 2 pt de respiro); selecionado em `accentColor` com texto branco e peso semibold, demais em `.primary`. Existe porque o `Picker` segmentado nativo do macOS não estica até a largura da linha | linha do grupo de controles, 468 pt | padrão, selecionado, aplicando (controles desabilitados até o eco do fone), somente leitura | [QCYBattery/QCYView.swift](QCYBattery/QCYView.swift) | componente + a11y (grupo `.contain` com rótulo, trait `.isSelected` no botão marcado) |
| Barra de abas segmentada (T14–T16, #8, #17) | botões de largura igual (`Status` e `Som`; `Toques` e `Ajustes` entram nas próximas entregas) em trilho `.quaternary` (raio 8, 2 pt de respiro); aba ativa elevada em `controlBackgroundColor` com sombra leve e texto `.primary` semibold | cabeçalho da janela, 468 pt | padrão, aba selecionada | [QCYBattery/QCYView.swift](QCYBattery/QCYView.swift) (`QCYTabBar`) | a11y (grupo `.contain` com rótulo, trait `.isSelected` na aba ativa) |
| Grade de efeitos de som (T14, #8, #17) | grade 2×2 fixa com os 4 efeitos medidos (`Espacial`, `Padrão`, `Pop`, `Graves pesados`); cada célula tem ícone SF Symbol em quadro 28×28, título e subtítulo, destacando a seleção em `accentColor` com texto branco. Sem paginação (2ª página não medida) | grupo na aba Som, 468 pt | padrão, selecionado, aplicando, erro, somente leitura | [QCYBattery/QCYSoundView.swift](QCYBattery/QCYSoundView.swift) (`QCYSoundEffectGrid`) | unitário no modelo (`QCYViewModelTests`) + a11y (grupo `.contain`, trait `.isSelected`) |
| Slider de balanço de canal (T14, #17) | slider 0...100 (centro 50) com rótulos `L100` e `R100`, valor atual (`Centro`, `L n` ou `R n` com `n = |valor-50|*2`) e botão `Redefinir` (= 50, desabilitado no centro); só envia ao fone ao soltar o slider | linha do grupo de som, 468 pt | centro, deslocado L/R, arrastando, aplicando, somente leitura | [QCYBattery/QCYSoundView.swift](QCYBattery/QCYSoundView.swift) (`QCYBalanceSlider`) | unitário no modelo e formatação (`QCYViewModelTests`) |
| Célula de gesto (T15, #8) | menu nativo por lado (`L` / `R`) em linha de gesto com lista de funções do fone ou `Macro no Mac…`; linhas pendentes de medição recebem selo `a medir` e fundo atenuado | colunas L/R na aba Toques, 468 pt | padrão, macro atribuída (borda/texto em `accentColor`), a medir (desabilitada), aplicando, erro | rascunho (protótipo) | a definir após aprovação |
| Editor de macro em sheet (T15, #8) | sheet modal sobre a janela com seletor de tipo (atalho de teclado, Atalho, app/URL, script), campo de valor, banner de aviso de permissões do usuário para scripts e ações `Testar`, `Cancelar`, `Salvar` | sheet 404 pt sobre janela 468 pt | aberto (tipo script com aviso visível) | rascunho (protótipo) | a definir após aprovação |
| Gravador de atalho global (T16, #8) | campo compacto com exibição do atalho (`⌘ ⇧ A`) e botão de limpar (`×`); ao gravar, destaca borda em `accentColor` e exibe "Pressione o atalho…" | linha de ajuste, 468 pt | definido, gravando | rascunho (protótipo) | a definir após aprovação |

## Símbolo
`lb.headphones.bluetooth` (copiado do LogiBattery) em `QCYBattery/Symbols.xcassets`.

## Ícone do app
Opção 2 aprovada por Lucas em 2026-11-13 (#140): par de fones esquerdo (branco) e direito (verde `#7FE3B0`) sobre o mesmo fundo escuro do LogiBattery. Fonte em `design/icon/qcy/appicon.svg`; os PNGs de `QCYBattery/Assets.xcassets/AppIcon.appiconset` saem dela com `rsvg-convert`.
