# QCYBattery

App de macOS para o fone QCY MeloBuds Pro: bateria de cada lado, firmware e controles de cancelamento de ruído, LDAC e modo jogo, pelo protocolo BLE do fone (o macOS mostra um número só, e às vezes errado).

Protocolo em [QCYKit](https://github.com/LucasStop/QCYKit). Bateria L/R também aparece no popover e no widget do [LogiBattery](https://github.com/LucasStop/LogiBattery).

```sh
brew install xcodegen swiftlint
xcodegen generate
xcodebuild -scheme QCYBattery -destination 'platform=macOS' build
```

| Doc | Conteúdo |
|---|---|
| [docs/PRD.md](docs/PRD.md) | Problema e histórias |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Partes e decisões |
| [docs/TESTING.md](docs/TESTING.md) | Testes |
| [DESIGN.md](DESIGN.md) | Design system |

Licença MIT.
