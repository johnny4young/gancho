# Contributing

Gancho is a closed-source product developed in the open with a small circle.

## Prerequisites

- macOS 26+, Xcode 26+
- XcodeGen: `brew install xcodegen`

## Workflow

```bash
make test      # fast feedback: package unit tests
make open      # generate + open the Xcode project
make format    # before every commit
make lint      # CI runs this with --strict
```

Conventions live in [AGENTS.md](AGENTS.md). Architecture decisions live in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md). Product scope and acceptance
criteria live in the Notion backlog — every PR should reference a backlog ID
(e.g. `E1.4`, `E13.2`).
