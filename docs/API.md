# API — QCYBattery

Status: aprovado em 2026-11-25

Sem API de rede nem contrato com outro processo: o app não tem widget, não escreve snapshot e não expõe URL scheme.

- Único contrato externo: a API pública do pacote [QCYKit](https://github.com/LucasStop/QCYKit/blob/main/docs/API.md), por tag semver (`from:` no `project.yml`).
- Entrada de linha de comando: `--read-only` desabilita toda escrita no fone (US-03).
