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

## Símbolo
`lb.headphones.bluetooth` (copiado do LogiBattery) em `QCYBattery/Symbols.xcassets`.

## Ícone do app
Opção 2 aprovada por Lucas em 2026-11-13 (#140): par de fones esquerdo (branco) e direito (verde `#7FE3B0`) sobre o mesmo fundo escuro do LogiBattery. Fonte em `design/icon/qcy/appicon.svg`; os PNGs de `QCYBattery/Assets.xcassets/AppIcon.appiconset` saem dela com `rsvg-convert`.
