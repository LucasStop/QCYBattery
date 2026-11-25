# QCYBattery

Contexto do repo para a CLI de IA. Regras globais em `~/.claude/CLAUDE.md` valem; aqui só o específico. `CLAUDE.md`, `AGENTS.md` e `GEMINI.md` são o mesmo arquivo (symlinks).

## O que é
App nativo macOS (janela e barra de menu) do fone QCY MeloBuds Pro: bateria por lado, firmware, MAC, controles de cena de ANC, LDAC e modo jogo, e (planejado) aba de som, gestos com macros no Mac, ajustes com regras por contexto e App Intents para Atalhos. O protocolo mora no pacote [QCYKit](https://github.com/LucasStop/QCYKit). Saiu do repo do [LogiBattery](https://github.com/LucasStop/LogiBattery) em 2026-11-25 (ADR 0008 de lá); issues e PRs até ali (#132, #135, #140, #150) estão no LogiBattery.
Perfil: monolito · Stack: Swift (SwiftUI, XcodeGen)

## Documentação (ler antes de mexer)
- [docs/PRD.md](docs/PRD.md): problema, histórias e critérios de aceite
- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md): partes e decisões
- [docs/TESTING.md](docs/TESTING.md): testes por parte e como rodar
- [DESIGN.md](DESIGN.md) e [design/telas.md](design/telas.md): design system e inventário de telas
- Protocolo: [QCYKit/docs/QCY.md](https://github.com/LucasStop/QCYKit/blob/main/docs/QCY.md)

## Regras de fluxo
- Mudança de comportamento atualiza PRD/ARCHITECTURE/TESTING no mesmo PR; bug corrigido ganha teste de regressão.
- Tela só é implementada com protótipo `aprovada` em `design/telas.md`. Pedido de aprovação sempre traz os prints (claro e escuro) salvos em `design/prints/`; o Lucas aprova olhando os prints. Componente ou token novo entra no `DESIGN.md` junto.
- Versão por PR (mesma regra do ADR 0007 do LogiBattery): `feat` sobe MINOR e `fix` sobe PATCH no próprio PR (`scripts/release.sh prepare`, último passo antes do merge, depois de rebasear na main), com a entrada do `CHANGELOG.md` reescrita com o porquê; os demais tipos não mexem na versão. Depois do merge com bump, avisar que falta `scripts/release.sh publish` e vigiar o `release-check` da tag.
- Mudança no protocolo vai para o QCYKit (PR lá, tag nova) e o bump de `from:` no `project.yml` vem aqui depois.

## Comandos
- Instalar: `brew install xcodegen swiftlint && xcodegen generate`
- Build: `xcodebuild -scheme QCYBattery -destination 'platform=macOS' build`
- Testes: `xcodebuild test -scheme QCYBattery -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO`
- Lint: `swiftlint --strict`
- Release: `scripts/release.sh prepare|publish`

## Convenções
- Swift 6 + SwiftUI, alvo macOS 14+; `project.yml` é a fonte, `.xcodeproj` não se edita à mão.
- Lógica no `QCYViewModel`, link com o fone atrás do protocolo `QCYLink` (fake nos testes e no preview).
- Escrita no fone só confirmada pelo eco; teste nunca escreve no fone real.
- Strings em `Localizable.xcstrings` (pt-BR e en). Sem log com MAC ou nome do usuário.
- Assinatura local com o time `69D4S5TF8S` (o `release.sh` usa); app instalado em `~/Applications/QCYBattery.app`. Depois de build, apagar `build.noindex/` e DerivedData.
- Bundle id `com.lucasstop.QCYBattery` fixo: trocar perde a permissão de Bluetooth concedida.

## Notas
- Fone: `84:AC:60:E9:90:6E`, firmware 2.0.6. Estojo não reporta (`0x00`); `0x0C` não responde, a cena `0x17` é a via de troca de ANC.
